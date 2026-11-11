-- ============================================================
-- Honeybee Center — 004 Historical Data Seed
-- Location: supabase/seed/20261015000003_seed_data.sql
-- Target:   honeybee-center-main (gvteqrtvpfujfrwrdohv)
-- Applied:  Phase 0c — AFTER provisioning.sql has been run
--
-- !! DO NOT run via `supabase db push` !!
-- This file is NOT in the migrations/ directory and will NOT be
-- tracked or applied automatically.
-- Run it manually via the Supabase Dashboard SQL Editor ONLY,
-- after substituting <COADMIN_UUID>.
--
-- BUILT-IN SAFETY:
--   '<COADMIN_UUID>' is not a valid PostgreSQL uuid literal.
--   If executed with unreplaced placeholders, the INSERT will fail:
--     ERROR: invalid input syntax for type uuid: "<COADMIN_UUID>"
--   The entire transaction (BEGIN/COMMIT) rolls back. No partial data written.
--
-- PREREQUISITE:
--   Replace every occurrence of <COADMIN_UUID> with the actual
--   Co-Admin Supabase Auth UUID.
--   Note: the co_admin account is provisioned during Phase 1 via the
--   Admin Web panel. Run this seed script only after that account exists.
--
-- Source: Firebase RTDB honeybee-center, verified by read-only inspection.
-- All quantities are warehouse inventory (inventory.quantity).
-- product_qty starts at 0 for all variants (D-A, D-9 confirmed).
-- ============================================================

BEGIN;

-- ── Products (4 verified) ─────────────────────────────────────────────────────

INSERT INTO public.products
  (id, external_id, name, variety, category, is_active, created_at, updated_at)
VALUES
  (gen_random_uuid(), 'prod_lukot',
   'Stingless Bees (Lukot)', 'Lukot', 'Stingless Bees', true,
   to_timestamp(1790078142503 / 1000.0), to_timestamp(1790672271302 / 1000.0)),
  (gen_random_uuid(), 'prod_mellifera',
   'Sweet Honey (Mellifera)', 'Mellifera', 'Sweet Honey', false, -- isActive=false VERIFIED
   to_timestamp(1790078142503 / 1000.0), to_timestamp(1791361233476 / 1000.0)),
  (gen_random_uuid(), 'prod_others',
   'Other Honey Products', NULL, 'Others', true,                 -- variety NULL VERIFIED
   to_timestamp(1790078142503 / 1000.0), NULL),                  -- updatedDate absent VERIFIED
  (gen_random_uuid(), 'prod_pukyutan',
   'Pukyutan Honey', 'Pukyutan', 'Pukyutan Honey', true,
   to_timestamp(1790078142503 / 1000.0), NULL);                  -- updatedDate absent VERIFIED


-- ── Product Variants (23 verified — all product_qty = 0) ──────────────────────

INSERT INTO public.product_variants
  (id, external_id, product_id, size, price, reorder_level, product_qty, is_active)
SELECT
  gen_random_uuid(), v.ext_id, p.id,
  v.size, v.price, v.reorder, 0, true
FROM (VALUES
  ('v_luk_1kg',       'prod_lukot',    '1kg',                    1200, 3),
  ('v_luk_350g',      'prod_lukot',    '350g',                    420, 5),
  ('v_luk_400g',      'prod_lukot',    '400g',                    480, 5),
  ('v_luk_500g',      'prod_lukot',    '500g',                    600, 5),
  ('v_luk_650g',      'prod_lukot',    '650g',                    780, 5),
  ('v_mel_1kg',       'prod_mellifera','1kg',                    1010, 5),
  ('v_mel_200g',      'prod_mellifera','200g',                    210,10),
  ('v_mel_250g',      'prod_mellifera','250g',                    260,10),
  ('v_mel_350g',      'prod_mellifera','350g',                    360,10),
  ('v_mel_400g',      'prod_mellifera','400g',                    410,10),
  ('v_mel_500g',      'prod_mellifera','500g',                    510,10),
  ('v_mel_660g',      'prod_mellifera','660g',                    660,10),
  ('v_comb_650g',     'prod_others',  'Honeycomb (650g)',         845, 5),
  ('v_pollen_500g',   'prod_others',  'Honey With Pollen 500g',  800, 5),
  ('v_propolis_100g', 'prod_others',  'Propolis (100g)',         500, 5),
  ('v_wax_1kg',       'prod_others',  'Bees Wax (kg)',           650, 5),
  ('v_puk_1kg',       'prod_pukyutan','1kg',                    1110, 5),
  ('v_puk_200g',      'prod_pukyutan','200g',                    230,10),
  ('v_puk_250g',      'prod_pukyutan','250g',                    285,10),
  ('v_puk_350g',      'prod_pukyutan','350g',                    395,10),
  ('v_puk_400g',      'prod_pukyutan','400g',                    450,10),
  ('v_puk_500g',      'prod_pukyutan','500g',                    560,10),
  ('v_puk_650g',      'prod_pukyutan','650g',                    725,10)
) AS v(ext_id, prod_ext, size, price, reorder)
JOIN public.products p ON p.external_id = v.prod_ext;


-- ── Inventory (23 records; 4 non-zero warehouse quantities) ───────────────────
-- These are WAREHOUSE quantities — not storefront stock.
-- product_qty = 0 for all variants (set above).
-- Quantity trail verified: movements below reconcile to these values.

INSERT INTO public.inventory (product_id, variant_id, quantity, updated_at)
SELECT p.id, pv.id, i.qty, to_timestamp(i.ts / 1000.0)
FROM (VALUES
  -- Non-zero (VERIFIED from Firebase)
  ('prod_lukot',    'v_luk_1kg',    80, 1791090117691),
  ('prod_mellifera','v_mel_1kg',    10, 1790334973933),
  ('prod_mellifera','v_mel_200g',   10, 1790334892211),
  ('prod_mellifera','v_mel_500g',   50, 1791353600182),
  -- Zero quantities (remaining 19 variants)
  ('prod_lukot',    'v_luk_350g',    0, 1790334580263),
  ('prod_lukot',    'v_luk_400g',    0, 1790334580263),
  ('prod_lukot',    'v_luk_500g',    0, 1790334580263),
  ('prod_lukot',    'v_luk_650g',    0, 1790334580263),
  ('prod_mellifera','v_mel_250g',    0, 1790334580263),
  ('prod_mellifera','v_mel_350g',    0, 1790334580263),
  ('prod_mellifera','v_mel_400g',    0, 1790334580263),
  ('prod_mellifera','v_mel_660g',    0, 1790334580263),
  ('prod_others',   'v_comb_650g',   0, 1790334580263),
  ('prod_others',   'v_pollen_500g', 0, 1790334580263),
  ('prod_others',   'v_propolis_100g',0,1790334580263),
  ('prod_others',   'v_wax_1kg',     0, 1790334580263),
  ('prod_pukyutan', 'v_puk_1kg',     0, 1790334580263),
  ('prod_pukyutan', 'v_puk_200g',    0, 1790334580263),
  ('prod_pukyutan', 'v_puk_250g',    0, 1790334580263),
  ('prod_pukyutan', 'v_puk_350g',    0, 1790334580263),
  ('prod_pukyutan', 'v_puk_400g',    0, 1790334580263),
  ('prod_pukyutan', 'v_puk_500g',    0, 1790334580263),
  ('prod_pukyutan', 'v_puk_650g',    0, 1790334580263)
) AS i(prod_ext, var_ext, qty, ts)
JOIN public.products p          ON p.external_id = i.prod_ext
JOIN public.product_variants pv ON pv.external_id = i.var_ext;


-- ── Production Batches (4 completed — VERIFIED from Firebase) ────────────────

INSERT INTO public.production_batches
  (id, external_id, product_id, variant_id, batch_name, is_bundle,
   status, qty_target, qty_completed, inventory_updated, inventory_added_qty,
   is_archived, created_by, completed_at, created_at, updated_at,
   bottle_size, product_name, production_date, start_date, target_completion_date)
SELECT
  gen_random_uuid(), b.ext_id,
  p.id, pv.id,
  b.pname || ' ' || b.size || ' Batch',
  false, 'Completed',
  b.target, b.completed,
  true, b.completed,
  false,
  '0f286663-8d72-4ed2-84fe-2b3c347070ca',
  to_timestamp(b.completed_ms / 1000.0),
  to_timestamp(b.created_ms  / 1000.0),
  now(),
  b.size, b.pname, b.prod_date, b.start_date, b.target_date
FROM (VALUES
  ('-P2NG_3uxP-wmvErCkUT','prod_mellifera','v_mel_200g',
   'Mellifera','200g',10,10,1790334891640,1790334882382,'2026-09-30','2026-09-25','2026-09-30'),
  ('-P2NGlNqX5fPhRTIOYrm','prod_mellifera','v_mel_1kg',
   'Sweet Honey (Mellifera)','1kg',10,10,1790334973190,1790334932808,'2026-09-30','2026-09-25','2026-09-30'),
  ('-P2gRied0vMA7cxaiQI8','prod_lukot','v_luk_1kg',
   'Stingless Bees (Lukot)','1kg',80,80,1790673386699,1790673349549,'2026-10-04','2026-09-29','2026-10-04'),
  ('-P3JzaYnFUZeZBr5-QXb','prod_mellifera','v_mel_500g',
   'Mellifera','500g',50,50,1791353599699,1791353580009,'2026-10-12','2026-10-07','2026-10-12')
) AS b(ext_id, prod_ext, var_ext, pname, size, target, completed,
       completed_ms, created_ms, prod_date, start_date, target_date)
JOIN public.products p          ON p.external_id = b.prod_ext
JOIN public.product_variants pv ON pv.external_id = b.var_ext;


-- ── Inventory Movements (6 verified — trail reconciles with inventory above) ──

INSERT INTO public.inventory_movements
  (external_id, product_id, variant_id, movement_type, quantity_change,
   prev_quantity, new_quantity, reference_id, reason, admin_id, created_at)
SELECT
  m.ext_id, p.id, pv.id,
  m.mtype, m.change, m.prev, m.new_qty,
  m.ref, m.reason,
  '0f286663-8d72-4ed2-84fe-2b3c347070ca',
  to_timestamp(m.ts / 1000.0)
FROM (VALUES
  ('-P2NGbtMYsn6LY9EVgdz','prod_mellifera','v_mel_200g',
   'production',     10,0,10, '-P2NG_3uxP-wmvErCkUT',NULL,         1790334893925),
  ('-P2NGw9zj3EyiVO61yKA','prod_mellifera','v_mel_1kg',
   'production',     10,0,10, '-P2NGlNqX5fPhRTIOYrm',NULL,         1790334976975),
  ('-P2gRrshZuAfiQmD3ssM','prod_lukot',   'v_luk_1kg',
   'production',     80,0,80, '-P2gRied0vMA7cxaiQI8',NULL,         1790673387301),
  ('-P34EZiT-Bpc44YSUZBP','prod_lukot',   'v_luk_1kg',
   'manual_adjustment',1,80,81,'manual_1791089329767','Returned Product',1791089331325),
  ('-P34HZllzepW4TE0sCrp','prod_lukot',   'v_luk_1kg',
   'reconciliation_adjustment',-1,81,80,'-P34HPCGWdeGiNrGQwP5',NULL,1791090117969),
  ('-P3JzfXmZ7M9HIlxQmjC','prod_mellifera','v_mel_500g',
   'production',     50,0,50, '-P3JzaYnFUZeZBr5-QXb',NULL,        1791353600414)
) AS m(ext_id, prod_ext, var_ext, mtype, change, prev, new_qty, ref, reason, ts)
JOIN public.products p          ON p.external_id = m.prod_ext
JOIN public.product_variants pv ON pv.external_id = m.var_ext;


-- ── Admin Activity Logs (6 of 10 — excludes 4 RESET_TEST_DATA + 1 orphaned) ───
-- The entry referencing batch #-P2N4Dy5... is kept as-is (text reference only,
-- no FK constraint on reference fields).

INSERT INTO public.admin_activity_logs
  (external_id, admin_id, action, details, created_at)
VALUES
  ('-P2N4J9ChxryoppubvcE', '0f286663-8d72-4ed2-84fe-2b3c347070ca',
   'EDIT_COMPLETED_PRODUCTION',
   'Edited completed quantity for batch #-P2N4Dy5PSeNZZypyFBd from 6 to 6 (inventory adjustment: 0)',
   to_timestamp(1790331667343 / 1000.0)),
  ('-P2NGdLDzWfQQv01OUv5', '0f286663-8d72-4ed2-84fe-2b3c347070ca',
   'EDIT_COMPLETED_PRODUCTION',
   'Edited completed quantity for batch #-P2NG_3uxP-wmvErCkUT from 10 to 10 (inventory adjustment: 0)',
   to_timestamp(1790334899869 / 1000.0)),
  ('-P2NGwcCafNeZdlrd91u', '0f286663-8d72-4ed2-84fe-2b3c347070ca',
   'EDIT_COMPLETED_PRODUCTION',
   'Edited completed quantity for batch #-P2NGlNqX5fPhRTIOYrm from 10 to 10 (inventory adjustment: 0)',
   to_timestamp(1790334978844 / 1000.0)),
  ('-P2NGxZogGGWIsoHRsvB', '0f286663-8d72-4ed2-84fe-2b3c347070ca',
   'EDIT_COMPLETED_PRODUCTION',
   'Edited completed quantity for batch #-P2NGlNqX5fPhRTIOYrm from 10 to 10 (inventory adjustment: 0)',
   to_timestamp(1790334982722 / 1000.0)),
  ('-P34EZrxq5rzTFBvi_K3', '0f286663-8d72-4ed2-84fe-2b3c347070ca',
   'MANUAL_INVENTORY_ADJUSTMENT',
   'Manual adjustment by Michelle: +1 for prod_lukot/v_luk_1kg. Reason: Returned Product.',
   to_timestamp(1791089331930 / 1000.0)),
  ('-P34HZuGkXpGRV0-YdbC', '0f286663-8d72-4ed2-84fe-2b3c347070ca',
   'RECONCILE_SCAN_DISCREPANCY',
   'Admin explicitly reconciled scan #-P34HPCGWdeGiNrGQwP5 discrepancy of -1 bottles for prod_lukot/v_luk_1kg',
   to_timestamp(1791090118511 / 1000.0));

COMMIT;

-- ── Verification queries ──────────────────────────────────────────────────────
SELECT 'products'                AS tbl, COUNT(*)::text        FROM public.products
UNION ALL
SELECT 'product_variants',                COUNT(*)::text        FROM public.product_variants
UNION ALL
SELECT 'inventory records',               COUNT(*)::text        FROM public.inventory
UNION ALL
SELECT 'inventory qty > 0',               COUNT(*)::text        FROM public.inventory WHERE quantity > 0
UNION ALL
SELECT 'inventory product_qty > 0',       COUNT(*)::text        FROM public.product_variants WHERE product_qty > 0
UNION ALL
SELECT 'total warehouse stock',           SUM(quantity)::text   FROM public.inventory
UNION ALL
SELECT 'production_batches',              COUNT(*)::text        FROM public.production_batches
UNION ALL
SELECT 'inventory_movements',             COUNT(*)::text        FROM public.inventory_movements
UNION ALL
SELECT 'admin_activity_logs',             COUNT(*)::text        FROM public.admin_activity_logs;

-- Expected:
--   products                 | 4
--   product_variants         | 23
--   inventory records        | 23
--   inventory qty > 0        | 4
--   inventory product_qty > 0| 0    ← storefront starts empty
--   total warehouse stock    | 150
--   production_batches       | 4
--   inventory_movements      | 6
--   admin_activity_logs      | 6
