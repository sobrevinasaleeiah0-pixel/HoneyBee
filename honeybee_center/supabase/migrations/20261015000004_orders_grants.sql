-- ============================================================
-- Honeybee Center — 004 Orders & QR Pickup Table Grants (Step 6.4)
-- Target:  honeybee-center-main (gvteqrtvpfujfrwrdohv)
-- Purpose: Grant minimal table-level SELECT and UPDATE permissions
--          to the authenticated role on orders and order_items.
--
-- Security Guarantees:
-- 1. Principle of Least Privilege:
--    - Zero grants are given to 'anon' (unauthenticated users cannot view or touch orders).
--    - 'authenticated' receives SELECT and UPDATE on public.orders.
--    - 'authenticated' receives SELECT on public.order_items.
-- 2. Row Level Security Enforcement:
--    - public.orders SELECT is governed by:
--        * "orders_read_admin" USING (public.is_active_admin())
--        * "orders_read_customer" USING (NOT public.is_active_admin() AND customer_id = ...)
--    - public.orders UPDATE is governed by:
--        * "orders_update_coadmin" USING (public.get_admin_role() = 'co_admin')
--    - public.order_items SELECT is governed by:
--        * "order_items_read_admin" USING (public.is_active_admin())
--        * "order_items_read_customer" USING (...)
-- 3. Invariant Preservation:
--    - Main Admin remains read-only / monitoring-only (UPDATE policy rejects non-co_admins).
--    - Inventory deduction is handled exclusively by complete_order() SECURITY DEFINER RPC.
-- ============================================================

GRANT SELECT, UPDATE ON public.orders TO authenticated;
GRANT SELECT ON public.order_items TO authenticated;
