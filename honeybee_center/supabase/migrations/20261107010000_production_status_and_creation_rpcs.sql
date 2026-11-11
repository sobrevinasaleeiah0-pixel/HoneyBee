BEGIN;

-- ════════════════════════════════════════════════════════════════════
-- Production Status and Creation RPCs
-- Migration: 20261107010000
--
-- Changes:
--   1. Extends production_batches.status CHECK to add 'Preparing' and
--      'Ready for Production' — the two bulk-workflow statuses written
--      by the Flutter app but absent from the existing 5-value constraint.
--
--   2. create_production_batch(text,text,int,text,text,text)
--      Standard batch creation. Resolves product/variant by external_id.
--
--   3. create_bulk_production_batch(uuid,text,text,int,text,text,text,text,jsonb)
--      Bundle batch + all production_batch_items in one transaction.
--
--   4. update_production_batch_status(uuid,text,int,int)
--      Authorized status/progress updates. Blocks 'Completed' target —
--      complete_production() remains the sole inventory-change path.
--
--   5. archive_production_batch(uuid)
--      Soft-archive. Sets is_archived=true, status='Archived'.
--      Does not delete records or touch inventory.
--
-- Does NOT change:
--   • complete_production() — already deployed, correct, idempotent
--   • RLS policies — existing batches/batch_items write policies cover co_admin
--   • public.production_history — no new write paths; SELECT-only policy kept
--   • Any inventory table, movement record, or quantity
--   • Firebase IoT paths, admin accounts, OTP, or any other business module
-- ════════════════════════════════════════════════════════════════════


-- ────────────────────────────────────────────────────────────────────
-- 1. Extend status CHECK constraint
--
-- Current constraint (5 values):
--   Planned | In Progress | Partially Completed | Completed | Archived
--
-- Adding (2 values used by Flutter bulk-production workflow):
--   Preparing | Ready for Production
--
-- Without this change, any new bulk batch INSERT via
-- create_bulk_production_batch() would fail with a constraint violation
-- because the Flutter app writes these statuses for supply-shortage
-- and supply-confirmed states.
-- ────────────────────────────────────────────────────────────────────

ALTER TABLE public.production_batches
  DROP CONSTRAINT production_batches_status_check;

ALTER TABLE public.production_batches
  ADD CONSTRAINT production_batches_status_check
  CHECK (status IN (
    'Planned',
    'In Progress',
    'Partially Completed',
    'Completed',
    'Archived',
    'Preparing',
    'Ready for Production'
  ));


-- ────────────────────────────────────────────────────────────────────
-- 2. create_production_batch
--
-- PURPOSE
--   Creates a standard (is_bundle = false) production batch.
--
-- AUTHORIZATION
--   Caller must be an active co_admin (get_admin_role() = 'co_admin').
--   created_by is always auth.uid() — never caller-supplied.
--   Owner (main_admin) is rejected.
--
-- INPUTS
--   p_product_external_id    Firebase-compatible external_id key,
--                            e.g. 'prod_mellifera'.
--   p_variant_external_id    Variant external_id, e.g. 'v_mel_250g'.
--   p_qty_target             Production quantity target. Must be >= 0.
--   p_start_date             Optional. Text date string (YYYY-MM-DD).
--   p_target_completion_date Optional. Text date string.
--   p_batch_name             Optional. Defaults to "ProductName Size".
--
-- RETURNS
--   uuid — The new production_batches.id.
--
-- VALIDATION
--   product/variant must be active and the variant must belong to
--   the resolved product. qty_target must be >= 0.
--
-- INVENTORY
--   Does NOT touch inventory. Inventory is updated only when
--   complete_production() is called after qty_completed >= qty_target.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_production_batch(
  p_product_external_id    text,
  p_variant_external_id    text,
  p_qty_target             integer,
  p_start_date             text    DEFAULT NULL,
  p_target_completion_date text    DEFAULT NULL,
  p_batch_name             text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_product  public.products%ROWTYPE;
  v_variant  public.product_variants%ROWTYPE;
  v_batch_id uuid;
BEGIN

  -- Authorization: co_admin only
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'create_production_batch: co_admin role required';
  END IF;

  -- Input validation
  IF p_product_external_id IS NULL
     OR pg_catalog.btrim(p_product_external_id) = '' THEN
    RAISE EXCEPTION
      'create_production_batch: p_product_external_id must not be null or empty';
  END IF;

  IF p_variant_external_id IS NULL
     OR pg_catalog.btrim(p_variant_external_id) = '' THEN
    RAISE EXCEPTION
      'create_production_batch: p_variant_external_id must not be null or empty';
  END IF;

  IF p_qty_target IS NULL OR p_qty_target < 0 THEN
    RAISE EXCEPTION
      'create_production_batch: p_qty_target must be >= 0 (got: %)',
      p_qty_target;
  END IF;

  -- Resolve product by external_id (must be active)
  SELECT * INTO v_product
    FROM public.products
   WHERE external_id = pg_catalog.btrim(p_product_external_id)
     AND is_active   = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'create_production_batch: product with external_id ''%'' not found or inactive',
      p_product_external_id;
  END IF;

  -- Resolve variant by external_id; must belong to the resolved product
  SELECT * INTO v_variant
    FROM public.product_variants
   WHERE external_id = pg_catalog.btrim(p_variant_external_id)
     AND product_id  = v_product.id
     AND is_active   = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'create_production_batch: variant ''%'' not found, inactive, or does '
      'not belong to product ''%''',
      p_variant_external_id, p_product_external_id;
  END IF;

  -- Insert batch record
  INSERT INTO public.production_batches (
    product_id,
    variant_id,
    batch_name,
    is_bundle,
    status,
    qty_target,
    qty_completed,
    inventory_updated,
    inventory_added_qty,
    is_archived,
    created_by,
    product_name,
    bottle_size,
    start_date,
    target_completion_date,
    production_date,
    created_at,
    updated_at
  )
  VALUES (
    v_product.id,
    v_variant.id,
    pg_catalog.coalesce(
      pg_catalog.nullif(pg_catalog.btrim(pg_catalog.coalesce(p_batch_name, '')), ''),
      v_product.name || ' ' || v_variant.size
    ),
    false,                   -- is_bundle: standard batch
    'Planned',               -- initial status
    p_qty_target,
    0,                       -- qty_completed starts at 0
    false,                   -- inventory_updated: idempotency flag, never preset
    NULL,                    -- inventory_added_qty: set only on completion
    false,                   -- is_archived
    auth.uid(),              -- created_by: always from JWT, never caller-supplied
    v_product.name,          -- product_name: preserved display field
    v_variant.size,          -- bottle_size: preserved display field
    p_start_date,
    p_target_completion_date,
    p_start_date,            -- production_date = start_date (legacy alias)
    now(),
    now()
  )
  RETURNING id INTO v_batch_id;

  RETURN v_batch_id;

END;
$$;

ALTER FUNCTION public.create_production_batch(text, text, integer, text, text, text)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.create_production_batch(text, text, integer, text, text, text)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_production_batch(text, text, integer, text, text, text)
  TO authenticated;


-- ────────────────────────────────────────────────────────────────────
-- 3. create_bulk_production_batch
--
-- PURPOSE
--   Creates a bundle (is_bundle = true) production batch AND all
--   production_batch_items atomically in a single transaction.
--   Multiple bulk plans for the same order_id are explicitly permitted
--   (no UNIQUE constraint on order_id exists or is added here).
--
-- AUTHORIZATION
--   Caller must be an active co_admin.
--   created_by = auth.uid() — never caller-supplied.
--
-- INPUTS
--   p_order_id               Supabase UUID of the customer order.
--                            Must reference an existing public.orders row.
--   p_customer_name          Customer display name string.
--   p_bundle_name            Display name for this bulk plan.
--   p_qty_target             Total production target across all items.
--   p_initial_status         Must be 'Preparing' or 'Ready for Production'.
--                            Caller determines this via supply shortage
--                            logic against warehouse inventory BEFORE
--                            calling this function.
--   p_items_summary          Optional free-text summary.
--   p_start_date             Optional text date.
--   p_target_completion_date Optional text date.
--   p_items                  JSONB array of item objects (schema below).
--                            May be an empty array [].
--
-- ITEMS JSONB SCHEMA (each element):
--   {
--     "product_external_id": "prod_mellifera",   -- required: Firebase ext key
--     "variant_external_id": "v_mel_250g",       -- required: Firebase ext key
--     "product_name":        "Sweet Honey",      -- required: display text
--     "bottle_size":         "250g",             -- required: display text
--     "qty_target":          10                  -- required: integer >= 0
--   }
--   product/variant UUIDs are resolved from external_id. Resolution
--   failure is non-fatal: product_id/variant_id stored as NULL, but
--   product_name and bottle_size are always stored from caller fields.
--
-- RETURNS
--   uuid — The new production_batches.id (the parent bundle record).
--
-- INVENTORY
--   Does NOT touch inventory. complete_production() is the sole path.
--   Supply shortage check is READ-ONLY (done in Flutter before calling).
--   Bulk restock does NOT add inventory — it only changes status.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_bulk_production_batch(
  p_order_id               uuid,
  p_customer_name          text,
  p_bundle_name            text,
  p_qty_target             integer,
  p_initial_status         text,
  p_items_summary          text    DEFAULT NULL,
  p_start_date             text    DEFAULT NULL,
  p_target_completion_date text    DEFAULT NULL,
  p_items                  jsonb   DEFAULT '[]'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_batch_id uuid;
  v_item     jsonb;
  v_prod_id  uuid;
  v_var_id   uuid;
  v_item_qty integer;
BEGIN

  -- Authorization: co_admin only
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'create_bulk_production_batch: co_admin role required';
  END IF;

  -- Input validation
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION
      'create_bulk_production_batch: p_order_id must not be null';
  END IF;

  -- Initial status must be one of the two bulk-entry statuses
  IF p_initial_status NOT IN ('Preparing', 'Ready for Production') THEN
    RAISE EXCEPTION
      'create_bulk_production_batch: p_initial_status must be ''Preparing'' '
      'or ''Ready for Production'' (got: ''%'')',
      p_initial_status;
  END IF;

  IF p_qty_target IS NULL OR p_qty_target < 0 THEN
    RAISE EXCEPTION
      'create_bulk_production_batch: p_qty_target must be >= 0 (got: %)',
      p_qty_target;
  END IF;

  -- Verify the referenced order exists (FK-enforced by DB, but explicit here
  -- for a clear error message)
  IF NOT EXISTS (SELECT 1 FROM public.orders WHERE id = p_order_id) THEN
    RAISE EXCEPTION
      'create_bulk_production_batch: order % not found', p_order_id;
  END IF;

  -- Insert parent bundle record
  INSERT INTO public.production_batches (
    is_bundle,
    batch_name,
    order_id,
    customer_name,
    status,
    qty_target,
    qty_completed,
    inventory_updated,
    inventory_added_qty,
    is_archived,
    created_by,
    items_summary,
    start_date,
    target_completion_date,
    production_date,
    created_at,
    updated_at
  )
  VALUES (
    true,
    pg_catalog.coalesce(
      pg_catalog.nullif(pg_catalog.btrim(pg_catalog.coalesce(p_bundle_name, '')), ''),
      'Wholesale Order'
    ),
    p_order_id,
    p_customer_name,
    p_initial_status,        -- 'Preparing' or 'Ready for Production'
    p_qty_target,
    0,                       -- qty_completed starts at 0
    false,                   -- inventory_updated: idempotency flag, never preset
    NULL,                    -- inventory_added_qty: set only on completion
    false,                   -- is_archived
    auth.uid(),              -- created_by: always from JWT
    p_items_summary,
    p_start_date,
    p_target_completion_date,
    p_start_date,            -- production_date = start_date (legacy alias)
    now(),
    now()
  )
  RETURNING id INTO v_batch_id;

  -- Insert child items atomically in the same transaction
  FOR v_item IN
    SELECT value
      FROM pg_catalog.jsonb_array_elements(
        pg_catalog.coalesce(p_items, '[]'::jsonb)
      )
  LOOP
    -- Resolve product UUID from external_id — non-fatal if not found
    v_prod_id := NULL;
    v_var_id  := NULL;

    SELECT id INTO v_prod_id
      FROM public.products
     WHERE external_id = pg_catalog.btrim(
               pg_catalog.coalesce(v_item->>'product_external_id', '')
           )
       AND is_active = true
     LIMIT 1;

    -- Resolve variant UUID — only if product resolved
    IF v_prod_id IS NOT NULL THEN
      SELECT id INTO v_var_id
        FROM public.product_variants
       WHERE external_id = pg_catalog.btrim(
                 pg_catalog.coalesce(v_item->>'variant_external_id', '')
             )
         AND product_id = v_prod_id
         AND is_active  = true
       LIMIT 1;
    END IF;

    -- Clamp qty_target to >= 0
    v_item_qty := pg_catalog.coalesce(
      (v_item->>'qty_target')::integer, 0
    );
    IF v_item_qty < 0 THEN v_item_qty := 0; END IF;

    INSERT INTO public.production_batch_items (
      batch_id,
      product_id,
      variant_id,
      product_name,
      bottle_size,
      qty_target,
      qty_completed,
      status
    )
    VALUES (
      v_batch_id,
      v_prod_id,   -- NULL if external_id did not resolve; non-fatal
      v_var_id,    -- NULL if external_id did not resolve; non-fatal
      pg_catalog.coalesce(
        pg_catalog.nullif(v_item->>'product_name', ''), 'Unknown'
      ),
      pg_catalog.coalesce(
        pg_catalog.nullif(v_item->>'bottle_size', ''), '-'
      ),
      v_item_qty,
      0,
      'Pending'
    );
  END LOOP;

  RETURN v_batch_id;

END;
$$;

ALTER FUNCTION public.create_bulk_production_batch(uuid, text, text, integer, text, text, text, text, jsonb)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.create_bulk_production_batch(uuid, text, text, integer, text, text, text, text, jsonb)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_bulk_production_batch(uuid, text, text, integer, text, text, text, text, jsonb)
  TO authenticated;


-- ────────────────────────────────────────────────────────────────────
-- 4. update_production_batch_status
--
-- PURPOSE
--   Updates a production batch's status and optionally its qty_completed
--   and/or qty_target. Covers all authorized status transitions EXCEPT
--   completion — which remains exclusively in complete_production().
--
-- AUTHORIZED TRANSITIONS
--   Planned             → In Progress
--   Preparing           → Ready for Production
--   Preparing           → Preparing       (after restock supply update)
--   Ready for Prod.     → In Progress
--   In Progress         → Partially Completed  (with updated qty)
--   In Progress         → In Progress          (qty update only)
--   Any non-archived    → Archived             (use archive_production_batch
--                                               for consistent behavior)
--
-- BLOCKED TRANSITION
--   Any → Completed  — blocked explicitly. Use complete_production() which
--                       handles inventory idempotency, inventory_movements,
--                       and the pessimistic inventory_updated flag.
--
-- AUTHORIZATION
--   Caller must be an active co_admin.
--
-- INPUTS
--   p_batch_id      UUID of the batch to update.
--   p_new_status    Target status. Must be a valid non-Completed value.
--   p_qty_completed Optional. If NULL, existing qty_completed is preserved.
--   p_qty_target    Optional. If NULL, existing qty_target is preserved.
--
-- SAFETY GUARDS
--   Archived batches cannot be updated.
--   'Completed' as a target is explicitly rejected.
--   Invalid status strings are rejected.
--   Row is locked FOR UPDATE to prevent concurrent mutation.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.update_production_batch_status(
  p_batch_id      uuid,
  p_new_status    text,
  p_qty_completed integer DEFAULT NULL,
  p_qty_target    integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_batch public.production_batches%ROWTYPE;
BEGIN

  -- Authorization: co_admin only
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION
      'update_production_batch_status: co_admin role required';
  END IF;

  -- Input validation
  IF p_batch_id IS NULL THEN
    RAISE EXCEPTION
      'update_production_batch_status: p_batch_id must not be null';
  END IF;

  IF p_new_status IS NULL
     OR pg_catalog.btrim(p_new_status) = '' THEN
    RAISE EXCEPTION
      'update_production_batch_status: p_new_status must not be null or empty';
  END IF;

  -- Block direct completion — complete_production() handles inventory
  -- idempotency and inventory_movements. Bypassing it would skip the
  -- inventory_updated pessimistic flag and could double-count inventory.
  IF p_new_status = 'Completed' THEN
    RAISE EXCEPTION
      'update_production_batch_status: use complete_production() to mark a '
      'batch as Completed — it is the only authorized inventory-change path';
  END IF;

  -- Validate the target status value
  IF p_new_status NOT IN (
    'Planned',
    'In Progress',
    'Partially Completed',
    'Archived',
    'Preparing',
    'Ready for Production'
  ) THEN
    RAISE EXCEPTION
      'update_production_batch_status: invalid status ''%''. '
      'Valid values: Planned, In Progress, Partially Completed, '
      'Archived, Preparing, Ready for Production',
      p_new_status;
  END IF;

  IF p_qty_completed IS NOT NULL AND p_qty_completed < 0 THEN
    RAISE EXCEPTION
      'update_production_batch_status: p_qty_completed must be >= 0';
  END IF;

  IF p_qty_target IS NOT NULL AND p_qty_target < 0 THEN
    RAISE EXCEPTION
      'update_production_batch_status: p_qty_target must be >= 0';
  END IF;

  -- Lock and read the batch row (prevents concurrent mutation)
  SELECT * INTO v_batch
    FROM public.production_batches
   WHERE id = p_batch_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION
      'update_production_batch_status: batch % not found', p_batch_id;
  END IF;

  -- Reject updates to archived batches
  IF v_batch.is_archived THEN
    RAISE EXCEPTION
      'update_production_batch_status: batch % is archived and cannot be updated',
      p_batch_id;
  END IF;

  -- Apply update — COALESCE preserves existing values when params are NULL
  UPDATE public.production_batches
     SET status        = p_new_status,
         qty_completed = pg_catalog.coalesce(p_qty_completed, qty_completed),
         qty_target    = pg_catalog.coalesce(p_qty_target,    qty_target),
         updated_at    = now()
   WHERE id = p_batch_id;

END;
$$;

ALTER FUNCTION public.update_production_batch_status(uuid, text, integer, integer)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.update_production_batch_status(uuid, text, integer, integer)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.update_production_batch_status(uuid, text, integer, integer)
  TO authenticated;


-- ────────────────────────────────────────────────────────────────────
-- 5. archive_production_batch
--
-- PURPOSE
--   Soft-archives a production batch. Sets is_archived = true and
--   status = 'Archived'. Safe to call on completed batches — the
--   inventory_updated flag and all historical movements are preserved.
--
-- IDEMPOTENCY
--   Calling on an already-archived batch is a no-op (no error).
--
-- AUTHORIZATION
--   Caller must be an active co_admin.
--
-- SAFETY
--   Does NOT delete the row or any child production_batch_items rows.
--   Does NOT touch inventory, inventory_movements, or production_history.
-- ────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.archive_production_batch(p_batch_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN

  -- Authorization: co_admin only
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'archive_production_batch: co_admin role required';
  END IF;

  IF p_batch_id IS NULL THEN
    RAISE EXCEPTION
      'archive_production_batch: p_batch_id must not be null';
  END IF;

  -- Verify the batch exists
  IF NOT EXISTS (
    SELECT 1 FROM public.production_batches WHERE id = p_batch_id
  ) THEN
    RAISE EXCEPTION
      'archive_production_batch: batch % not found', p_batch_id;
  END IF;

  -- Idempotent update — if already archived the WHERE condition
  -- on is_archived = false skips the UPDATE silently
  UPDATE public.production_batches
     SET is_archived = true,
         status      = 'Archived',
         updated_at  = now()
   WHERE id          = p_batch_id
     AND is_archived = false;

END;
$$;

ALTER FUNCTION public.archive_production_batch(uuid)
  OWNER TO postgres;

REVOKE ALL ON FUNCTION public.archive_production_batch(uuid)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.archive_production_batch(uuid)
  TO authenticated;

COMMIT;
