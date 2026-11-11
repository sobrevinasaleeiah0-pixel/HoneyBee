-- ============================================================
-- Honeybee Center — 003 Narrow Table Grants (Read-Only Stage 6)
-- Target:  honeybee-center-main (gvteqrtvpfujfrwrdohv)
-- Purpose: Grant minimal, table-specific SELECT permissions required
--          for Product & Warehouse Inventory read operations.
--
-- Security Guarantees:
-- 1. Principle of Least Privilege: Replaces broad "ALL TABLES" grants
--    with strictly scoped, per-table SELECT privileges.
-- 2. Sensitive Table Isolation: Zero grants are provided to anon or
--    authenticated roles for sensitive tables (admins, customers,
--    orders, order_items, audit movements, activity logs, sessions).
-- 3. Warehouse Protection: "public.inventory" is NOT granted to anon.
--    Only authenticated users receive SELECT on inventory, and RLS
--    policy "inventory_read_admin" strictly restricts visibility
--    to active admins (is_active_admin() = true).
-- 4. Catalog Browsing: "public.products" and "public.product_variants"
--    are granted SELECT to anon and authenticated. RLS policies
--    "products_read_public" and "variants_read_public" ensure non-admin
--    callers can only see rows where is_active = true.
-- ============================================================

-- 1. Products Catalog (Storefront & Admin Read)
-- Public catalog read allowed under RLS policy: products_read_public (is_active = true)
-- Full catalog read allowed for admins under RLS policy: products_read_admin (is_active_admin())
GRANT SELECT ON public.products TO anon, authenticated;

-- 2. Product Variants (Storefront & Admin Read)
-- Public variants read allowed under RLS policy: variants_read_public (is_active = true)
-- Full variants read allowed for admins under RLS policy: variants_read_admin (is_active_admin())
GRANT SELECT ON public.product_variants TO anon, authenticated;

-- 3. Warehouse Inventory (Admin Only)
-- NOT granted to anon (defense-in-depth privilege denial at table level).
-- Granted to authenticated only, strictly governed by RLS policy:
-- "inventory_read_admin" USING (public.is_active_admin()).
-- Non-admin authenticated accounts receive 0 rows.
GRANT SELECT ON public.inventory TO authenticated;

-- 4. Admin Management & Session Profile (Admin Only)
-- NOT granted to anon (defense-in-depth privilege denial at table level).
-- Granted to authenticated only, strictly governed by RLS policy:
-- "admins_read" USING (public.is_active_admin()).
-- Non-admin authenticated accounts receive 0 rows.
GRANT SELECT ON public.admins TO authenticated;

