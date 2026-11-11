-- Step 6.4: Atomically validate and confirm QR pickup.
--
-- This migration is local only until explicitly approved for remote application.
-- It composes complete_order() and the pickup audit update in one transaction,
-- so failed validation or stock deduction cannot leave a partial pickup record.
CREATE OR REPLACE FUNCTION public.confirm_order_pickup(
  p_order_id uuid,
  p_order_reference text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_admin_name text;
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'confirm_order_pickup: co_admin role required';
  END IF;

  SELECT *
    INTO v_order
    FROM public.orders
   WHERE id = p_order_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'confirm_order_pickup: order % not found', p_order_id;
  END IF;

  IF NULLIF(trim(p_order_reference), '') IS NULL
     OR v_order.order_reference IS NULL
     OR v_order.order_reference <> upper(trim(p_order_reference)) THEN
    RAISE EXCEPTION 'confirm_order_pickup: order reference does not match';
  END IF;

  IF v_order.picked_up_at IS NOT NULL OR v_order.product_qty_deducted THEN
    RAISE EXCEPTION 'confirm_order_pickup: order has already been processed';
  END IF;

  IF v_order.order_status <> 'Ready for Pickup' THEN
    RAISE EXCEPTION
      'confirm_order_pickup: order % is not ready for pickup (status: %)',
      p_order_id, v_order.order_status;
  END IF;

  IF v_order.payment_status NOT IN ('Confirmed', 'Paid') THEN
    RAISE EXCEPTION
      'confirm_order_pickup: payment is not confirmed (status: %)',
      v_order.payment_status;
  END IF;

  SELECT name
    INTO v_admin_name
    FROM public.admins
   WHERE id = auth.uid()
     AND status = 'active';

  IF v_admin_name IS NULL THEN
    RAISE EXCEPTION 'confirm_order_pickup: active administrator not found';
  END IF;

  -- complete_order validates role/payment/state and deducts product_qty
  -- transactionally. Any error rolls back both the deduction and pickup audit.
  PERFORM public.complete_order(p_order_id);

  UPDATE public.orders
     SET picked_up_at = now(),
         picked_up_by = v_admin_name,
         updated_at = now()
   WHERE id = p_order_id
     AND picked_up_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'confirm_order_pickup: pickup was already recorded';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_order_pickup(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.confirm_order_pickup(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.confirm_order_pickup(uuid, text) TO authenticated;
