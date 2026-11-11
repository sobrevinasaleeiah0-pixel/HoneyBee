-- ============================================================
-- Honeybee Center — 002 RPC Functions
-- Target:  honeybee-center-main (gvteqrtvpfujfrwrdohv)
-- Applied: Phase 0a (same transaction as schema)
--
-- LOCKING CONVENTION (enforced in every function below):
--   1. public.orders             (FOR UPDATE if touched)
--   2. public.production_batches (FOR UPDATE if touched)
--   3. public.product_variants   (FOR UPDATE — ALWAYS before inventory)
--   4. public.inventory          (FOR UPDATE — ALWAYS last)
--
-- SECURITY DEFINER ownership:
--   All functions are created by this migration running as 'postgres'.
--   They execute as 'postgres' regardless of the calling role.
--   'postgres' is not 'service_role'; it is the database superuser.
--   Every function carries SET search_path = public to prevent schema
--   injection attacks via a shadow 'public' schema.
--
-- EXECUTE grants summary:
--   Helper functions      → authenticated, anon   (needed for RLS evaluation)
--   Trigger functions     → REVOKED from PUBLIC   (Postgres internal use only)
--   Business RPCs         → authenticated only    (internal role check rejects non-co_admin)
--   create_customer_order → authenticated only    (internal check rejects admins)
--   request_otp_session   → NO GRANT              (service_role only)
-- ============================================================


-- ══════════════════════════════════════════════════════════════
-- GRANT BLOCK FOR HELPER FUNCTIONS (defined in 001_schema.sql)
-- ══════════════════════════════════════════════════════════════
-- These already exist; we add explicit grants here for clarity.

GRANT EXECUTE ON FUNCTION public.get_admin_role()    TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_active_admin()   TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_main_admin()     TO authenticated, anon;

-- Trigger functions are invoked by Postgres internally, not via the REST API.
REVOKE ALL ON FUNCTION public.prevent_role_escalation()  FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_order_reference() FROM PUBLIC;


-- ══════════════════════════════════════════════════════════════
-- FUNCTION: complete_order
-- ══════════════════════════════════════════════════════════════
--
-- Deducts product_qty (storefront pool) per line item when a co_admin
-- marks an order Completed.
--
-- Transaction safety:
--   • FOR UPDATE on orders row — serializes concurrent completion attempts.
--   • product_qty_deducted flag set BEFORE the deduction loop (pessimistic
--     lock), mirroring the existing RTDB design in database_service.dart.
--   • stock validation raises EXCEPTION before any deduction; if any item
--     fails, the entire transaction rolls back — no partial deduction.
--   • FOR UPDATE on product_variants rows within the loop — prevents a
--     concurrent replenish from changing qty between our read and write.
--
-- Stock validation (D-A):
--   • Validates order_status IN ('Confirmed','Preparing','Ready for Pickup').
--   • Validates payment_status IN ('Confirmed','Paid').
--   • Checks product_qty >= requested quantity BEFORE deducting.
--   • RAISES EXCEPTION (and rolls back) if insufficient — never silently clamps.
--
-- Low-stock notifications (R2):
--   • After each item deduction, if product_qty <= reorder_level:
--     fires STOREFRONT_LOW_STOCK notification.
--   • If product_qty reaches 0: fires STOREFRONT_OUT_OF_STOCK notification.
--   • Uses STOREFRONT_* prefix to distinguish from warehouse OUT_OF_STOCK/LOW_STOCK.
--   • Uses the notifications deduplication index (type, related_id WHERE is_read=false)
--     to avoid duplicate unread alerts.  ON CONFLICT DO NOTHING prevents errors.
--   • reorder_level is also the storefront threshold (no separate column exists;
--     see schema comment in Section 5 of 001_schema.sql).
--
CREATE OR REPLACE FUNCTION public.complete_order(
  p_order_id uuid
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_order   public.orders%ROWTYPE;
  v_item    public.order_items%ROWTYPE;
  v_variant public.product_variants%ROWTYPE;
  v_new_pq  integer;
BEGIN
  -- ── Role check ────────────────────────────────────────────────────────────
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'complete_order: co_admin role required';
  END IF;

  -- ── Lock order row (locking convention: orders first) ─────────────────────
  SELECT * INTO v_order FROM public.orders
   WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'complete_order: order % not found', p_order_id;
  END IF;

  -- ── Idempotency guard ─────────────────────────────────────────────────────
  IF v_order.product_qty_deducted THEN
    -- Already processed: ensure status fields are correct and return cleanly.
    UPDATE public.orders
       SET order_status = 'Completed',
           payment_status = 'Paid',
           updated_at = now()
     WHERE id = p_order_id;
    RETURN;
  END IF;

  -- ── Order state validation (D-A) ──────────────────────────────────────────
  IF v_order.order_status NOT IN ('Confirmed', 'Preparing', 'Ready for Pickup') THEN
    RAISE EXCEPTION
      'complete_order: order % cannot be completed from status ''%'' '
      '(must be Confirmed, Preparing, or Ready for Pickup)',
      p_order_id, v_order.order_status;
  END IF;

  IF v_order.payment_status NOT IN ('Confirmed', 'Paid') THEN
    RAISE EXCEPTION
      'complete_order: order % payment is not confirmed '
      '(current payment_status: ''%'')',
      p_order_id, v_order.payment_status;
  END IF;

  -- ── Set idempotency flag BEFORE deduction loop ────────────────────────────
  -- Mirrors the existing RTDB pattern: set pessimistically before the loop
  -- so a crash mid-loop does not allow a second completion attempt to
  -- re-enter and double-deduct.
  UPDATE public.orders
     SET product_qty_deducted = true,
         order_status         = 'Completed',
         payment_status       = 'Paid',
         updated_at           = now()
   WHERE id = p_order_id;

  -- ── Stock validation and deduction loop ───────────────────────────────────
  -- Lock product_variants before deducting (locking convention: variants before inventory).
  -- If ANY item fails the stock check, the entire transaction rolls back,
  -- including the idempotency flag update above.
  FOR v_item IN
    SELECT * FROM public.order_items WHERE order_id = p_order_id
  LOOP
    -- Lock this variant row for the duration of the transaction
    SELECT * INTO v_variant FROM public.product_variants
     WHERE id = v_item.variant_id FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'complete_order: variant % referenced by order % no longer exists',
        v_item.variant_id, p_order_id;
    END IF;

    -- Stock validation — EXCEPTION triggers full rollback (D-A)
    IF v_variant.product_qty < v_item.quantity THEN
      RAISE EXCEPTION
        'complete_order: insufficient storefront stock for variant % '
        '(available: %, requested: %). '
        'Replenish product_qty before completing this order.',
        v_item.variant_id, v_variant.product_qty, v_item.quantity;
    END IF;

    -- Deduct without GREATEST — we already validated qty >= requested
    UPDATE public.product_variants
       SET product_qty = product_qty - v_item.quantity,
           updated_at  = now()
     WHERE id = v_item.variant_id
     RETURNING product_qty INTO v_new_pq;

    -- ── Low-stock notifications (R2) ─────────────────────────────────────────
    -- ON CONFLICT DO NOTHING prevents duplicate unread notifications.
    IF v_new_pq = 0 THEN
      INSERT INTO public.notifications (type, message, related_id)
      VALUES (
        'STOREFRONT_OUT_OF_STOCK',
        'Storefront stock for ' || v_item.bottle_size
          || ' (' || v_item.product_name || ') reached zero '
          || 'after order ' || p_order_id::text
          || '. Use Products → Replenish to restore availability.',
        v_item.variant_id::text
      )
      ON CONFLICT (type, related_id) WHERE is_read = false
      DO NOTHING;

    ELSIF v_new_pq <= v_variant.reorder_level THEN
      INSERT INTO public.notifications (type, message, related_id)
      VALUES (
        'STOREFRONT_LOW_STOCK',
        'Storefront stock for ' || v_item.bottle_size
          || ' (' || v_item.product_name || ') is low ('
          || v_new_pq || ' units remaining). '
          || 'Consider replenishing from warehouse inventory.',
        v_item.variant_id::text
      )
      ON CONFLICT (type, related_id) WHERE is_read = false
      DO NOTHING;
    END IF;
  END LOOP;

  -- ── Completion notification ───────────────────────────────────────────────
  INSERT INTO public.notifications (type, message, related_id)
  VALUES (
    'NEW_SALE',
    'Order ' || p_order_id::text || ' marked as completed.',
    p_order_id::text
  )
  ON CONFLICT (type, related_id) WHERE is_read = false
  DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_order(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.complete_order(uuid) TO authenticated;


-- ══════════════════════════════════════════════════════════════
-- FUNCTION: complete_production
-- ══════════════════════════════════════════════════════════════
--
-- Increases warehouse inventory.quantity when a production batch completes.
-- Does NOT touch product_qty (storefront pool).
--
-- Idempotency: inventory_updated flag locked under FOR UPDATE.
-- Guards: qty_completed > 0; bundle items must have non-NULL product_id.
--
CREATE OR REPLACE FUNCTION public.complete_production(
  p_batch_id uuid
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_batch    public.production_batches%ROWTYPE;
  v_item     public.production_batch_items%ROWTYPE;
  v_prev_qty  integer;
  v_total_added integer := 0;  -- tracks total inventory added across bundle items
BEGIN
  -- ── Role check ────────────────────────────────────────────────────────────
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'complete_production: co_admin role required';
  END IF;

  -- ── Lock batch row ────────────────────────────────────────────────────────
  SELECT * INTO v_batch FROM public.production_batches
   WHERE id = p_batch_id FOR UPDATE;

  IF NOT FOUND THEN RETURN false; END IF;

  -- ── Idempotency guard ─────────────────────────────────────────────────────
  IF v_batch.inventory_updated OR v_batch.is_archived THEN
    RETURN false;
  END IF;

  -- ── Quantity guard ────────────────────────────────────────────────────────
  IF v_batch.qty_completed <= 0 THEN
    RAISE EXCEPTION
      'complete_production: batch % has no completed quantity — '
      'update completed quantity before finishing', p_batch_id;
  END IF;

  -- ── Set idempotency flag BEFORE inventory change ───────────────────────────
  UPDATE public.production_batches
     SET inventory_updated = true,
         status            = 'Completed',
         completed_at      = now(),
         updated_at        = now()
   WHERE id = p_batch_id;

  IF NOT v_batch.is_bundle THEN
    -- ── Standard batch ────────────────────────────────────────────────────
    -- Lock variants before inventory (locking convention)
    PERFORM 1 FROM public.product_variants
     WHERE id = v_batch.variant_id FOR UPDATE;

    SELECT quantity INTO v_prev_qty FROM public.inventory
     WHERE product_id = v_batch.product_id
       AND variant_id = v_batch.variant_id
     FOR UPDATE;

    UPDATE public.inventory
       SET quantity   = quantity + v_batch.qty_completed,
           updated_at = now()
     WHERE product_id = v_batch.product_id
       AND variant_id = v_batch.variant_id;

    INSERT INTO public.inventory_movements
      (product_id, variant_id, movement_type, quantity_change,
       prev_quantity, new_quantity, reference_id, admin_id)
    VALUES
      (v_batch.product_id, v_batch.variant_id, 'production',
       v_batch.qty_completed,
       v_prev_qty, v_prev_qty + v_batch.qty_completed,
       p_batch_id::text,
       auth.uid());

    UPDATE public.production_batches
       SET inventory_added_qty = v_batch.qty_completed
     WHERE id = p_batch_id;

  ELSE
    -- ── Bundle batch ──────────────────────────────────────────────────────
    FOR v_item IN
      SELECT * FROM public.production_batch_items WHERE batch_id = p_batch_id
    LOOP
      -- Guard: skip items with zero qty or missing FKs
      CONTINUE WHEN v_item.qty_completed <= 0;
      CONTINUE WHEN v_item.variant_id IS NULL;
      CONTINUE WHEN v_item.product_id  IS NULL; -- F6 fix

      -- Lock variant before inventory (locking convention)
      PERFORM 1 FROM public.product_variants
       WHERE id = v_item.variant_id FOR UPDATE;

      SELECT quantity INTO v_prev_qty FROM public.inventory
       WHERE variant_id = v_item.variant_id FOR UPDATE;

      UPDATE public.inventory
         SET quantity   = quantity + v_item.qty_completed,
             updated_at = now()
       WHERE variant_id = v_item.variant_id;

      INSERT INTO public.inventory_movements
        (product_id, variant_id, movement_type, quantity_change,
         prev_quantity, new_quantity, reference_id, admin_id)
      VALUES
        (v_item.product_id, v_item.variant_id, 'production',
         v_item.qty_completed,
         v_prev_qty, v_prev_qty + v_item.qty_completed,
         p_batch_id::text || '_' || v_item.id::text,
         auth.uid());

      v_total_added := v_total_added + v_item.qty_completed;
    END LOOP;

    -- Record total inventory added for bundle (mirrors standard batch behaviour)
    UPDATE public.production_batches
       SET inventory_added_qty = v_total_added
     WHERE id = p_batch_id;
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_production(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.complete_production(uuid) TO authenticated;


-- ══════════════════════════════════════════════════════════════
-- FUNCTION: replenish_product_qty
-- ══════════════════════════════════════════════════════════════
--
-- Transfers qty units from warehouse inventory.quantity → product_qty.
-- Both rows locked together in one transaction — no partial state possible.
-- Lock order: product_variants THEN inventory (locking convention: variants first).
--
CREATE OR REPLACE FUNCTION public.replenish_product_qty(
  p_variant_id uuid,
  p_qty        integer,
  p_admin_id   uuid DEFAULT NULL
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_variant public.product_variants%ROWTYPE;
  v_inv     public.inventory%ROWTYPE;
  v_prev_inv  integer;
  v_new_inv   integer;
  v_prev_pq   integer;
  v_new_pq    integer;
BEGIN
  -- ── Role check ────────────────────────────────────────────────────────────
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'replenish_product_qty: co_admin role required';
  END IF;

  -- ── Audit attribution check ───────────────────────────────────────────────
  IF p_admin_id IS NOT NULL AND p_admin_id != auth.uid() THEN
    RAISE EXCEPTION 'replenish_product_qty: audit attribution mismatch (cannot record on behalf of another admin)';
  END IF;

  IF p_qty <= 0 THEN RETURN 'INVALID_QTY'; END IF;

  -- ── Lock product_variants FIRST (locking convention) ─────────────────────
  SELECT * INTO v_variant FROM public.product_variants
   WHERE id = p_variant_id FOR UPDATE;

  IF NOT FOUND THEN RETURN 'NO_VARIANT'; END IF;

  -- ── Lock inventory AFTER product_variants (locking convention) ────────────
  SELECT * INTO v_inv FROM public.inventory
   WHERE variant_id = p_variant_id FOR UPDATE;

  IF NOT FOUND THEN RETURN 'NO_INVENTORY_NODE'; END IF;

  IF v_inv.quantity < p_qty THEN
    RETURN 'INSUFFICIENT_INVENTORY:' || v_inv.quantity::text;
  END IF;

  v_prev_inv := v_inv.quantity;
  v_new_inv  := v_inv.quantity - p_qty;
  v_prev_pq  := v_variant.product_qty;
  v_new_pq   := v_variant.product_qty + p_qty;

  UPDATE public.inventory
     SET quantity   = v_new_inv,
         updated_at = now()
   WHERE variant_id = p_variant_id;

  UPDATE public.product_variants
     SET product_qty = v_new_pq,
         updated_at  = now()
   WHERE id = p_variant_id;

  INSERT INTO public.inventory_movements
    (product_id, variant_id, movement_type, quantity_change,
     prev_quantity, new_quantity, reference_id, admin_id, notes)
  VALUES
    (v_inv.product_id, p_variant_id, 'product_replenishment',
     -p_qty, v_prev_inv, v_new_inv,
     'replenish_' || extract(epoch from now())::bigint::text,
     auth.uid(),
     'Product QTY: ' || v_prev_pq || ' → ' || v_new_pq);

  RETURN 'SUCCESS';
END;
$$;

REVOKE ALL ON FUNCTION public.replenish_product_qty(uuid, integer, uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.replenish_product_qty(uuid, integer, uuid) TO authenticated;


-- ══════════════════════════════════════════════════════════════
-- FUNCTION: adjust_inventory
-- ══════════════════════════════════════════════════════════════
--
-- Manual warehouse stock correction (increase or decrease).
-- Records the ACTUAL applied change (not the requested change) if clamped.
-- Fires LOW_STOCK / OUT_OF_STOCK notification for warehouse pool.
-- Lock order: product_variants (lock for notification read of reorder_level)
--             THEN inventory (locking convention).
--
CREATE OR REPLACE FUNCTION public.adjust_inventory(
  p_variant_id   uuid,
  p_change       integer,
  p_type         text,
  p_reference_id text    DEFAULT NULL,
  p_reason       text    DEFAULT NULL,
  p_notes        text    DEFAULT NULL,
  p_admin_id     uuid    DEFAULT NULL
)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_variant       public.product_variants%ROWTYPE;
  v_inv           public.inventory%ROWTYPE;
  v_new_qty       integer;
  v_actual_change integer;
BEGIN
  -- ── Role check ────────────────────────────────────────────────────────────
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'adjust_inventory: co_admin role required';
  END IF;

  -- ── Audit attribution check ───────────────────────────────────────────────
  IF p_admin_id IS NOT NULL AND p_admin_id != auth.uid() THEN
    RAISE EXCEPTION 'adjust_inventory: audit attribution mismatch (cannot record on behalf of another admin)';
  END IF;

  -- ── Lock product_variants first (locking convention) ──────────────────────
  SELECT * INTO v_variant FROM public.product_variants
   WHERE id = p_variant_id FOR UPDATE;

  -- ── Lock inventory after (locking convention) ─────────────────────────────
  SELECT * INTO v_inv FROM public.inventory
   WHERE variant_id = p_variant_id FOR UPDATE;

  IF NOT FOUND THEN
    -- Auto-create inventory record if missing (mirrors RTDB behaviour).
    -- v_variant is already populated and locked from the SELECT above.
    INSERT INTO public.inventory (product_id, variant_id, quantity)
      VALUES (v_variant.product_id, p_variant_id, GREATEST(0, p_change));
    RETURN GREATEST(0, p_change);
  END IF;

  v_new_qty       := GREATEST(0, v_inv.quantity + p_change);
  v_actual_change := v_new_qty - v_inv.quantity; -- actual applied (may differ from p_change if clamped)

  UPDATE public.inventory
     SET quantity   = v_new_qty,
         updated_at = now()
   WHERE variant_id = p_variant_id;

  -- Record actual applied change, with a note if clamping occurred (F7 fix)
  INSERT INTO public.inventory_movements
    (product_id, variant_id, movement_type, quantity_change,
     prev_quantity, new_quantity, reference_id, reason, notes, admin_id)
  VALUES
    (v_inv.product_id, p_variant_id, p_type,
     v_actual_change,
     v_inv.quantity, v_new_qty,
     p_reference_id, p_reason,
     CASE
       WHEN v_actual_change != p_change
         THEN 'Clamped to 0: requested ' || p_change
              || ', applied ' || v_actual_change
              || COALESCE('. ' || p_notes, '')
       ELSE p_notes
     END,
     auth.uid());

  -- Warehouse low-stock notification (uses existing OUT_OF_STOCK / LOW_STOCK types)
  IF v_new_qty <= v_variant.reorder_level THEN
    INSERT INTO public.notifications (type, message, related_id)
    VALUES (
      CASE WHEN v_new_qty = 0 THEN 'OUT_OF_STOCK' ELSE 'LOW_STOCK' END,
      CASE WHEN v_new_qty = 0
        THEN v_variant.size || ' warehouse stock is OUT OF STOCK'
        ELSE v_variant.size || ' warehouse stock is low (' || v_new_qty || ' remaining)'
      END,
      p_variant_id::text
    )
    ON CONFLICT (type, related_id) WHERE is_read = false
    DO NOTHING;
  END IF;

  RETURN v_new_qty;
END;
$$;

REVOKE ALL ON FUNCTION public.adjust_inventory(uuid, integer, text, text, text, text, uuid)
  FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.adjust_inventory(uuid, integer, text, text, text, text, uuid)
  TO authenticated;


-- ══════════════════════════════════════════════════════════════
-- FUNCTION: create_customer_order
-- ══════════════════════════════════════════════════════════════
--
-- Secure customer order creation RPC (D-E).
-- • Resolves or auto-creates the customer record from auth.uid() (D-G).
-- • Validates: authenticated non-admin caller, active variants,
--   product_qty > 0, quantity > 0, quantity <= 50 per line (R1),
--   quantity <= product_qty at submission time.
-- • Prices and total_amount are computed from the database (never from client).
-- • Does NOT deduct product_qty — deduction happens at complete_order.
-- • Returns {order_id, total_amount, item_count} as jsonb.
--
CREATE OR REPLACE FUNCTION public.create_customer_order(
  p_customer_name  text,
  p_customer_phone text,
  p_items          jsonb  -- [{variant_id: "uuid", quantity: int}, ...]
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_caller_uid   uuid    := auth.uid();
  v_caller_email text    := auth.jwt() ->> 'email';
  v_customer     public.customers%ROWTYPE;
  v_order_id     uuid;
  v_item         jsonb;
  v_variant      public.product_variants%ROWTYPE;
  v_product      public.products%ROWTYPE;
  v_subtotal     numeric(10,2);
  v_total        numeric(10,2) := 0;
  v_item_count   integer       := 0;
  v_qty          integer;
BEGIN
  -- ── Must be authenticated ─────────────────────────────────────────────────
  IF v_caller_uid IS NULL THEN
    RAISE EXCEPTION 'create_customer_order: authentication required';
  END IF;
  -- ── Must NOT be an admin ──────────────────────────────────────────────────
  IF public.is_active_admin() THEN
    RAISE EXCEPTION
      'create_customer_order: admin accounts cannot submit customer orders';
  END IF;

  -- ── At least one item required ────────────────────────────────────────────
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'create_customer_order: at least one item is required';
  END IF;

  -- ── Validate ALL items before any INSERT (fail fast) ─────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF (v_item->>'variant_id') IS NULL THEN
      RAISE EXCEPTION 'create_customer_order: variant_id is required for every item';
    END IF;

    v_qty := (v_item->>'quantity')::int;

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION
        'create_customer_order: quantity must be a positive integer '
        '(variant %)', v_item->>'variant_id';
    END IF;

    -- R1: maximum 50 units per line item
    IF v_qty > 50 THEN
      RAISE EXCEPTION
        'create_customer_order: maximum 50 units per variant per order '
        '(requested % for variant %)', v_qty, v_item->>'variant_id';
    END IF;

    -- Variant must be active, parent product active, product_qty > 0
    SELECT pv.* INTO v_variant
      FROM public.product_variants pv
      JOIN public.products p ON p.id = pv.product_id
     WHERE pv.id = (v_item->>'variant_id')::uuid
       AND pv.is_active = true
       AND p.is_active  = true
       AND pv.product_qty > 0;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'create_customer_order: variant % is unavailable or out of stock',
        v_item->>'variant_id';
    END IF;

    -- Point-in-time stock check (R1 — no reservation, documented limitation)
    IF v_qty > v_variant.product_qty THEN
      RAISE EXCEPTION
        'create_customer_order: only % unit(s) available for variant %',
        v_variant.product_qty, v_item->>'variant_id';
    END IF;

    v_item_count := v_item_count + 1;
  END LOOP;

  -- ── Resolve or auto-create customer record ────────────────────────────────
  -- auth_uid is stable — does not change when email changes (D-G)
  SELECT * INTO v_customer FROM public.customers
   WHERE auth_uid = v_caller_uid;

  IF NOT FOUND THEN
    INSERT INTO public.customers (auth_uid, name, email, phone, status)
    VALUES (v_caller_uid, p_customer_name, v_caller_email,
            p_customer_phone, 'active')
    RETURNING * INTO v_customer;
  END IF;

  -- ── Create order shell ────────────────────────────────────────────────────
  INSERT INTO public.orders
    (customer_id, customer_name, customer_email, customer_phone,
     order_status, payment_status, total_amount)
  VALUES
    (v_customer.id, p_customer_name, v_caller_email, p_customer_phone,
     'Pending', 'Pending', 0)
  RETURNING id INTO v_order_id;

  -- ── Insert items with prices from DB ─────────────────────────────────────
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT pv.* INTO v_variant FROM public.product_variants pv
     WHERE pv.id = (v_item->>'variant_id')::uuid;
    SELECT p.* INTO v_product FROM public.products p
     WHERE p.id = v_variant.product_id;

    v_qty      := (v_item->>'quantity')::int;
    v_subtotal := v_variant.price * v_qty;
    v_total    := v_total + v_subtotal;

    INSERT INTO public.order_items
      (order_id, product_id, variant_id, product_name, bottle_size,
       unit_price, quantity, subtotal)
    VALUES
      (v_order_id,
       v_variant.product_id,
       v_variant.id,
       v_product.name || ' (' || v_variant.size || ')',
       v_variant.size,
       v_variant.price,    -- price from DB, never from client payload
       v_qty,
       v_subtotal);
  END LOOP;

  -- ── Set server-computed total ─────────────────────────────────────────────
  UPDATE public.orders SET total_amount = v_total WHERE id = v_order_id;

  RETURN jsonb_build_object(
    'order_id',     v_order_id,
    'total_amount', v_total,
    'item_count',   v_item_count
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_customer_order(text, text, jsonb) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.create_customer_order(text, text, jsonb) TO authenticated;


-- ══════════════════════════════════════════════════════════════
-- FUNCTION: request_otp_session
-- ══════════════════════════════════════════════════════════════
--
-- Called ONLY by the OTP Edge Function via service_role.
-- No GRANT to authenticated or anon — REVOKE from PUBLIC.
-- service_role bypasses all EXECUTE restrictions.
--
-- Implements the rate-limiting and cooldown logic that was previously
-- handled via Firebase RTDB ETag operations.
-- Uses SELECT FOR UPDATE to serialize concurrent OTP requests for the
-- same email (equivalent to RTDB ETag optimistic concurrency).
--
CREATE OR REPLACE FUNCTION public.request_otp_session(
  p_email_hash        text,
  p_user_id           uuid,
  p_otp_hash          text,
  p_expires_at        timestamptz,
  p_resend_at         timestamptz,
  p_send_window_start timestamptz
)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_existing public.otp_sessions%ROWTYPE;
  v_now      timestamptz := now();
BEGIN
  -- Lock existing row (or create) under FOR UPDATE to prevent race conditions.
  SELECT * INTO v_existing FROM public.otp_sessions
   WHERE email_hash = p_email_hash FOR UPDATE;

  IF FOUND THEN
    -- Enforce resend cooldown
    IF v_now < v_existing.resend_at THEN
      RETURN 'COOLDOWN';
    END IF;
    -- Enforce hourly rate limit
    IF (v_now - v_existing.send_window_start) < interval '1 hour'
       AND v_existing.send_count >= 5 THEN
      RETURN 'RATE_LIMITED';
    END IF;

    UPDATE public.otp_sessions SET
      otp_hash          = p_otp_hash,
      expires_at        = p_expires_at,
      attempts          = 0,
      send_count        = CASE
                            WHEN (v_now - v_existing.send_window_start) < interval '1 hour'
                            THEN v_existing.send_count + 1
                            ELSE 1
                          END,
      send_window_start = CASE
                            WHEN (v_now - v_existing.send_window_start) < interval '1 hour'
                            THEN v_existing.send_window_start
                            ELSE p_send_window_start
                          END,
      resend_at         = p_resend_at,
      created_at        = v_now
    WHERE email_hash = p_email_hash;

  ELSE
    INSERT INTO public.otp_sessions
      (email_hash, user_id, otp_hash, expires_at, attempts,
       send_count, send_window_start, resend_at)
    VALUES
      (p_email_hash, p_user_id, p_otp_hash, p_expires_at, 0,
       1, p_send_window_start, p_resend_at);
  END IF;

  RETURN 'OK';
END;
$$;

-- NO GRANT — service_role only
REVOKE ALL ON FUNCTION public.request_otp_session(
  text, uuid, text, timestamptz, timestamptz, timestamptz
) FROM PUBLIC;
