-- ============================================================
-- Honeybee Center — RPC Function Fixes & Invariant Hardening
-- Migration: 20261015000002_rpc_fixes.sql
-- Target:    honeybee-center-main (gvteqrtvpfujfrwrdohv)
--
-- Fixes applied:
--   1. complete_order: Non-mutating idempotency guard; prevents overwriting
--      order_status and payment_status if stock is already deducted.
--   2. complete_production: Ensures warehouse inventory row exists before
--      updating quantity, preventing silent zero-update and NULL prev_quantity.
--   3. adjust_inventory: Adds IF NOT FOUND check for product_variants,
--      validates movement_type and reason, and guarantees that auto-creating
--      an inventory row still logs an inventory_movements audit record.
-- ============================================================

-- ── 1. complete_order ────────────────────────────────────────────────────────

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
  -- Role check: co_admin required
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'complete_order: co_admin role required';
  END IF;

  -- Lock order row (locking convention: orders first)
  SELECT * INTO v_order FROM public.orders
   WHERE id = p_order_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'complete_order: order % not found', p_order_id;
  END IF;

  -- Idempotency guard: return cleanly if stock is already deducted
  -- Do not overwrite existing status fields
  IF v_order.product_qty_deducted THEN
    RETURN;
  END IF;

  -- Order state validation
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

  -- Set idempotency flag before deduction loop
  UPDATE public.orders
     SET product_qty_deducted = true,
         order_status         = 'Completed',
         payment_status       = 'Paid',
         updated_at           = now()
   WHERE id = p_order_id;

  -- Stock validation and deduction loop
  FOR v_item IN
    SELECT * FROM public.order_items WHERE order_id = p_order_id
  LOOP
    SELECT * INTO v_variant FROM public.product_variants
     WHERE id = v_item.variant_id FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION
        'complete_order: variant % referenced by order % no longer exists',
        v_item.variant_id, p_order_id;
    END IF;

    IF v_variant.product_qty < v_item.quantity THEN
      RAISE EXCEPTION
        'complete_order: insufficient storefront stock for variant % '
        '(available: %, requested: %). '
        'Replenish product_qty before completing this order.',
        v_item.variant_id, v_variant.product_qty, v_item.quantity;
    END IF;

    UPDATE public.product_variants
       SET product_qty = product_qty - v_item.quantity,
           updated_at  = now()
     WHERE id = v_item.variant_id
     RETURNING product_qty INTO v_new_pq;

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

  -- Completion notification
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


-- ── 2. complete_production ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.complete_production(
  p_batch_id uuid
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_batch       public.production_batches%ROWTYPE;
  v_item        public.production_batch_items%ROWTYPE;
  v_prev_qty    integer;
  v_total_added integer := 0;
BEGIN
  -- Role check: co_admin required
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'complete_production: co_admin role required';
  END IF;

  -- Lock batch row
  SELECT * INTO v_batch FROM public.production_batches
   WHERE id = p_batch_id FOR UPDATE;

  IF NOT FOUND THEN RETURN false; END IF;

  -- Idempotency guard
  IF v_batch.inventory_updated OR v_batch.is_archived THEN
    RETURN false;
  END IF;

  -- Quantity guard
  IF v_batch.qty_completed <= 0 THEN
    RAISE EXCEPTION
      'complete_production: batch % has no completed quantity — '
      'update completed quantity before finishing', p_batch_id;
  END IF;

  -- Set idempotency flag before inventory change
  UPDATE public.production_batches
     SET inventory_updated = true,
         status            = 'Completed',
         completed_at      = now(),
         updated_at        = now()
   WHERE id = p_batch_id;

  IF NOT v_batch.is_bundle THEN
    -- Standard batch
    PERFORM 1 FROM public.product_variants
     WHERE id = v_batch.variant_id FOR UPDATE;

    SELECT quantity INTO v_prev_qty FROM public.inventory
     WHERE product_id = v_batch.product_id
       AND variant_id = v_batch.variant_id
     FOR UPDATE;

    IF NOT FOUND THEN
      INSERT INTO public.inventory (product_id, variant_id, quantity)
      VALUES (v_batch.product_id, v_batch.variant_id, 0);
      v_prev_qty := 0;
    END IF;

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
    -- Bundle batch
    FOR v_item IN
      SELECT * FROM public.production_batch_items WHERE batch_id = p_batch_id
    LOOP
      CONTINUE WHEN v_item.qty_completed <= 0;
      CONTINUE WHEN v_item.variant_id IS NULL;
      CONTINUE WHEN v_item.product_id  IS NULL;

      PERFORM 1 FROM public.product_variants
       WHERE id = v_item.variant_id FOR UPDATE;

      SELECT quantity INTO v_prev_qty FROM public.inventory
       WHERE variant_id = v_item.variant_id FOR UPDATE;

      IF NOT FOUND THEN
        INSERT INTO public.inventory (product_id, variant_id, quantity)
        VALUES (v_item.product_id, v_item.variant_id, 0);
        v_prev_qty := 0;
      END IF;

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

    UPDATE public.production_batches
       SET inventory_added_qty = v_total_added
     WHERE id = p_batch_id;
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_production(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.complete_production(uuid) TO authenticated;


-- ── 3. adjust_inventory ──────────────────────────────────────────────────────

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
  v_prev_qty      integer;
BEGIN
  -- Role check: co_admin required
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'adjust_inventory: co_admin role required';
  END IF;

  -- Audit attribution check
  IF p_admin_id IS NOT NULL AND p_admin_id != auth.uid() THEN
    RAISE EXCEPTION 'adjust_inventory: audit attribution mismatch (cannot record on behalf of another admin)';
  END IF;

  -- Validate movement type
  IF p_type NOT IN (
    'production', 'production_adjustment',
    'sale', 'product_replenishment',
    'manual_adjustment', 'reconciliation_adjustment'
  ) THEN
    RAISE EXCEPTION 'adjust_inventory: invalid movement type ''%''', p_type;
  END IF;

  -- Validate reason requirement
  IF p_type IN ('manual_adjustment', 'reconciliation_adjustment') AND (p_reason IS NULL OR trim(p_reason) = '') THEN
    RAISE EXCEPTION 'adjust_inventory: reason is required for %', p_type;
  END IF;

  -- Lock product_variants first (locking convention)
  SELECT * INTO v_variant FROM public.product_variants
   WHERE id = p_variant_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'adjust_inventory: variant % not found', p_variant_id;
  END IF;

  -- Lock inventory after (locking convention)
  SELECT * INTO v_inv FROM public.inventory
   WHERE variant_id = p_variant_id FOR UPDATE;

  IF NOT FOUND THEN
    -- Auto-create inventory record initialized to 0
    INSERT INTO public.inventory (product_id, variant_id, quantity)
      VALUES (v_variant.product_id, p_variant_id, 0)
      RETURNING * INTO v_inv;
  END IF;

  v_prev_qty      := v_inv.quantity;
  v_new_qty       := GREATEST(0, v_prev_qty + p_change);
  v_actual_change := v_new_qty - v_prev_qty;

  UPDATE public.inventory
     SET quantity   = v_new_qty,
         updated_at = now()
   WHERE variant_id = p_variant_id;

  -- Record actual applied change in movement audit trail
  INSERT INTO public.inventory_movements
    (product_id, variant_id, movement_type, quantity_change,
     prev_quantity, new_quantity, reference_id, reason, notes, admin_id)
  VALUES
    (v_variant.product_id, p_variant_id, p_type,
     v_actual_change,
     v_prev_qty, v_new_qty,
     p_reference_id, p_reason,
     CASE
       WHEN v_actual_change != p_change
         THEN 'Clamped to 0: requested ' || p_change
              || ', applied ' || v_actual_change
              || COALESCE('. ' || p_notes, '')
       ELSE p_notes
     END,
     auth.uid());

  -- Warehouse low-stock notification
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
