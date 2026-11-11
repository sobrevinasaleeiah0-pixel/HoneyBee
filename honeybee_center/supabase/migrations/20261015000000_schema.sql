-- ============================================================
-- Honeybee Center — 001 Schema
-- Target:  honeybee-center-main (gvteqrtvpfujfrwrdohv)
-- Applied: Phase 0a
-- Do NOT execute against honeybee-center-otp or any live system
--           without explicit approval.
--
-- Objects created:
--   3 helper functions, 2 trigger functions, 2 triggers,
--   14 tables, 24 indexes, 34 RLS policies,
--   4 column/table-level REVOKEs
-- ============================================================


-- ══════════════════════════════════════════════════════════════
-- SECTION 1 — ADMINS TABLE DEFINITION
-- Must exist before helper functions that query public.admins.
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.admins (
  id          uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name        text        NOT NULL,
  email       text        NOT NULL,
  role        text        NOT NULL DEFAULT 'co_admin'
                          CHECK (role IN ('main_admin', 'co_admin')),
  status      text        NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active', 'inactive')),
  created_by  uuid        REFERENCES public.admins(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  last_login  timestamptz,
  CONSTRAINT admins_email_unique UNIQUE (email)
);


-- ══════════════════════════════════════════════════════════════
-- SECTION 2 — HELPER FUNCTIONS
-- Must exist before any RLS policy references them.
-- ══════════════════════════════════════════════════════════════

-- Returns the active role for the calling Supabase JWT user.
-- Returns NULL if the caller has no row in public.admins or is inactive.
CREATE OR REPLACE FUNCTION public.get_admin_role()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT role
    FROM public.admins
   WHERE id = auth.uid()
     AND status = 'active'
$$;

-- Returns true if the caller is any active admin (main or co).
CREATE OR REPLACE FUNCTION public.is_active_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admins
     WHERE id = auth.uid() AND status = 'active'
  )
$$;

-- Returns true if the caller is an active main_admin specifically.
CREATE OR REPLACE FUNCTION public.is_main_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admins
     WHERE id = auth.uid()
       AND role = 'main_admin'
       AND status = 'active'
  )
$$;

-- ── Role escalation trigger ───────────────────────────────────────────────────
--
-- Fires on BEFORE INSERT OR UPDATE.
--
-- Bootstrap design (replaces the removed GUC-based bypass):
--
--   The trigger permits a direct-connection INSERT (auth.uid() IS NULL)
--   only when:
--     • The admins table is empty (bootstrap not yet run), AND
--     • The new row's role is 'main_admin'.
--   Any other direct-connection INSERT is rejected with a clear exception.
--   The window closes permanently once the first row is committed.
--
-- Why auth.uid() IS NULL correctly identifies the direct-postgres path:
--   • auth.uid() reads the 'sub' JWT claim via current_setting().
--   • Supabase anon and service_role JWTs carry no 'sub' claim →
--     auth.uid() returns NULL for those requests too.
--   • However, anon INSERT is stopped by the RLS admins_insert policy
--     (WITH CHECK (is_main_admin()) → false) before the trigger fires.
--   • service_role bypasses RLS and would reach the trigger with NULL uid.
--     The empty-table check still applies — service_role may insert the
--     bootstrap row, but so could a direct psql connection. Both are
--     privileged administrative actions. The idx_one_main_admin unique
--     index independently enforces at most one main_admin row.
--
-- For authenticated API callers (auth.uid() IS NOT NULL):
--   INSERT: blocks assigning main_admin unless the caller is already main_admin.
--   UPDATE: blocks promoting to main_admin or changing own role.
--
CREATE OR REPLACE FUNCTION public.prevent_role_escalation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_count integer;
BEGIN

  -- ══ INSERT path ════════════════════════════════════════════════════════════

  IF TG_OP = 'INSERT' THEN

    IF auth.uid() IS NULL THEN
      -- Direct database connection (Dashboard SQL Editor, psql, db push).
      -- auth.uid() is also NULL for anon and service_role API requests, but
      -- those are stopped earlier: anon by RLS, service_role by the check below.
      SELECT COUNT(*) INTO v_count FROM public.admins;

      IF v_count = 0 THEN
        -- Bootstrap window: table is empty. Only main_admin is permitted.
        IF NEW.role != 'main_admin' THEN
          RAISE EXCEPTION
            'prevent_role_escalation: the initial admin row must have '
            'role = ''main_admin'' (got: ''%'')', NEW.role;
        END IF;
        RETURN NEW;
      END IF;

      -- Bootstrap is complete. Reject all further NULL-uid INSERTs.
      RAISE EXCEPTION
        'prevent_role_escalation: admin bootstrap is complete. '
        'Use the Admin Web panel to add co-admin accounts.';
    END IF;

    -- ── Authenticated API callers (auth.uid() IS NOT NULL) ──────────────────
    IF NEW.role = 'main_admin' AND NOT public.is_main_admin() THEN
      RAISE EXCEPTION
        'prevent_role_escalation: only main_admin can create a main_admin '
        'account';
    END IF;

    RETURN NEW;
  END IF;

  -- ══ UPDATE path ════════════════════════════════════════════════════════════

  IF TG_OP = 'UPDATE' THEN
    -- Block role promotion to main_admin by any non-main-admin.
    -- is_main_admin() returns false when auth.uid() is NULL, so direct-
    -- connection UPDATEs that attempt promotion are also blocked here.
    IF NEW.role = 'main_admin' AND OLD.role != 'main_admin' THEN
      IF NOT public.is_main_admin() THEN
        RAISE EXCEPTION
          'prevent_role_escalation: only main_admin can assign main_admin role';
      END IF;
    END IF;

    -- Block self-role changes for authenticated API callers only.
    IF auth.uid() IS NOT NULL
       AND NEW.id = auth.uid()
       AND NEW.role != OLD.role THEN
      RAISE EXCEPTION
        'prevent_role_escalation: admins cannot change their own role';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER prevent_role_escalation
  BEFORE INSERT OR UPDATE ON public.admins
  FOR EACH ROW EXECUTE FUNCTION public.prevent_role_escalation();

-- One-main-admin constraint (approved T5.3 fix).
-- Enforces that exactly one main_admin row can exist at any time.
-- Applies regardless of how the row is inserted (API, trusted provisioning, or Dashboard).
-- The provisioning script inserts the main_admin row before the co_admin row,
-- so if a second main_admin were accidentally added it would fail here.
--
-- Pre-deployment duplicate check (run read-only before applying):
--   SELECT COUNT(*) FROM public.admins WHERE role = 'main_admin';
--   Expected: 0 (database is empty before Phase 0a).
--
CREATE UNIQUE INDEX idx_one_main_admin
  ON public.admins (role)
  WHERE role = 'main_admin';

-- RLS
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins_read"   ON public.admins FOR SELECT
  USING (public.is_active_admin());

CREATE POLICY "admins_insert" ON public.admins FOR INSERT
  WITH CHECK (public.is_main_admin());

CREATE POLICY "admins_update" ON public.admins FOR UPDATE
  USING (
    (public.is_main_admin() AND role = 'co_admin')
    OR id = auth.uid()
  )
  WITH CHECK (
    role != 'main_admin' OR public.is_main_admin()
  );

CREATE POLICY "admins_delete" ON public.admins FOR DELETE
  USING (public.is_main_admin() AND role = 'co_admin');


-- ══════════════════════════════════════════════════════════════
-- SECTION 3 — OTP SESSION TABLES
-- Accessible ONLY via service_role (Edge Function).
-- RLS enabled with no permissive policies = deny all client access.
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.otp_sessions (
  email_hash        text        PRIMARY KEY,
  user_id           uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  otp_hash          text        NOT NULL,
  expires_at        timestamptz NOT NULL,
  attempts          integer     NOT NULL DEFAULT 0,
  send_count        integer     NOT NULL DEFAULT 1,
  send_window_start timestamptz NOT NULL DEFAULT now(),
  resend_at         timestamptz NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.password_reset_sessions (
  token_hash  text        PRIMARY KEY,
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email       text        NOT NULL,
  expires_at  timestamptz NOT NULL,
  claimed_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.otp_sessions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.password_reset_sessions ENABLE ROW LEVEL SECURITY;
-- No CREATE POLICY → deny all to anon and authenticated.


-- ══════════════════════════════════════════════════════════════
-- SECTION 4 — PRODUCTS
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.products (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id  text        UNIQUE NOT NULL, -- Firebase key e.g. 'prod_pukyutan'
  name         text        NOT NULL,
  variety      text,                        -- NULL for prod_others (verified)
  category     text,
  description  text,
  is_active    boolean     NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz          -- NULL for prod_others, prod_pukyutan (verified)
);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "products_read_admin"    ON public.products FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "products_read_public"   ON public.products FOR SELECT
  USING (is_active = true);
CREATE POLICY "products_write_coadmin" ON public.products FOR ALL
  USING  (public.get_admin_role() = 'co_admin')
  WITH CHECK (public.get_admin_role() = 'co_admin');


-- ══════════════════════════════════════════════════════════════
-- SECTION 5 — PRODUCT VARIANTS
-- ══════════════════════════════════════════════════════════════
--
-- LOCKING CONVENTION (applies to all RPC functions):
--   1. public.orders             (if touched)
--   2. public.production_batches (if touched)
--   3. public.product_variants   ← lock BEFORE inventory
--   4. public.inventory          ← lock LAST
-- Violating this order between concurrent transactions causes deadlock.
--
-- product_qty    = storefront stock (deducted by complete_order)
-- reorder_level  = warehouse reorder threshold (used by _checkLowStock in
--                  database_service.dart and by adjust_inventory RPC).
--                  It is ALSO used as the storefront low-stock threshold in
--                  complete_order (R2).  Both pools share this threshold
--                  because no separate storefront_reorder_level exists yet.
--                  A future migration may add that column if differentiation
--                  is needed.
--
CREATE TABLE public.product_variants (
  id             uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id    text    UNIQUE NOT NULL, -- Firebase key e.g. 'v_puk_250g'
  product_id     uuid    NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  size           text    NOT NULL,
  price          integer NOT NULL CHECK (price > 0),
  reorder_level  integer NOT NULL DEFAULT 10 CHECK (reorder_level >= 0),
  product_qty    integer NOT NULL DEFAULT 0  CHECK (product_qty >= 0),
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz,
  UNIQUE (product_id, size)
);

CREATE INDEX idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX idx_variants_size       ON public.product_variants(size);
CREATE INDEX idx_variants_is_active  ON public.product_variants(is_active);

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "variants_read_admin"    ON public.product_variants FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "variants_read_public"   ON public.product_variants FOR SELECT
  USING (is_active = true);
CREATE POLICY "variants_write_coadmin" ON public.product_variants FOR ALL
  USING  (public.get_admin_role() = 'co_admin')
  WITH CHECK (public.get_admin_role() = 'co_admin');

-- product_qty is ONLY writable by SECURITY DEFINER RPC functions.
-- No client (anon or authenticated) can UPDATE it directly via the REST API.
REVOKE UPDATE (product_qty) ON public.product_variants FROM authenticated, anon;


-- ══════════════════════════════════════════════════════════════
-- SECTION 6 — INVENTORY (warehouse pool)
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.inventory (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  uuid        NOT NULL REFERENCES public.products(id),
  variant_id  uuid        NOT NULL REFERENCES public.product_variants(id),
  quantity    integer     NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (product_id, variant_id)
);

CREATE INDEX idx_inventory_variant_id ON public.inventory(variant_id);

ALTER TABLE public.inventory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventory_read_admin"    ON public.inventory FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "inventory_insert_coadmin" ON public.inventory FOR INSERT
  WITH CHECK (public.get_admin_role() = 'co_admin');
CREATE POLICY "inventory_update_coadmin" ON public.inventory FOR UPDATE
  USING (public.get_admin_role() = 'co_admin');


-- ══════════════════════════════════════════════════════════════
-- SECTION 7 — INVENTORY MOVEMENTS (append-only audit trail)
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.inventory_movements (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id      text        UNIQUE,     -- Firebase push key for migrated records
  product_id       uuid        NOT NULL REFERENCES public.products(id),
  variant_id       uuid        NOT NULL REFERENCES public.product_variants(id),
  movement_type    text        NOT NULL
                               CHECK (movement_type IN (
                                 'production', 'production_adjustment',
                                 'sale', 'product_replenishment',
                                 'manual_adjustment', 'reconciliation_adjustment'
                               )),
  quantity_change  integer     NOT NULL,
  prev_quantity    integer     NOT NULL,
  new_quantity     integer     NOT NULL,
  reference_id     text,
  reason           text,
  notes            text,
  admin_id         uuid        REFERENCES public.admins(id),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_inv_movements_variant  ON public.inventory_movements(variant_id);
CREATE INDEX idx_inv_movements_type     ON public.inventory_movements(movement_type);
CREATE INDEX idx_inv_movements_created  ON public.inventory_movements(created_at DESC);

ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "movements_read_admin" ON public.inventory_movements FOR SELECT
  USING (public.is_active_admin());

-- Clients cannot write to the audit trail.
-- Only SECURITY DEFINER RPC functions (running as postgres) can INSERT.
REVOKE INSERT, UPDATE, DELETE ON public.inventory_movements FROM authenticated, anon;


-- ══════════════════════════════════════════════════════════════
-- SECTION 8 — CUSTOMERS
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.customers (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_uid    uuid        UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  name        text        NOT NULL,
  email       text        UNIQUE,
  phone       text,
  address     text,
  status      text        NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active', 'inactive')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_customers_email    ON public.customers(email);
CREATE INDEX idx_customers_auth_uid ON public.customers(auth_uid);

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "customers_read_admin"  ON public.customers FOR SELECT
  USING (public.is_active_admin());
-- Customers read and manage their own record via auth_uid (D-G: stable UUID ownership)
CREATE POLICY "customers_read_own"    ON public.customers FOR SELECT
  USING (auth_uid = auth.uid() AND NOT public.is_active_admin());
CREATE POLICY "customers_update_own"  ON public.customers FOR UPDATE
  USING (auth_uid = auth.uid() AND NOT public.is_active_admin())
  WITH CHECK (auth_uid = auth.uid() AND NOT public.is_active_admin());


-- ══════════════════════════════════════════════════════════════
-- SECTION 9 — ORDERS
-- ══════════════════════════════════════════════════════════════
--
-- Customers never INSERT orders directly.
-- All customer order creation goes through create_customer_order RPC (D-E).
-- Ownership is tied to customers.auth_uid, not email (D-G).
--

CREATE TABLE public.orders (
  id                       uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id              uuid          REFERENCES public.customers(id),
  customer_name            text          NOT NULL,
  customer_email           text,         -- contact info only, NOT ownership key
  customer_phone           text,
  customer_address         text,
  order_date               date          NOT NULL DEFAULT CURRENT_DATE,
  order_status             text          NOT NULL DEFAULT 'Pending'
                                         CHECK (order_status IN (
                                           'Pending', 'Confirmed', 'Preparing',
                                           'Ready for Pickup', 'Completed', 'Cancelled'
                                         )),
  payment_method           text,
  payment_status           text          NOT NULL DEFAULT 'Pending',
  payment_reference        text,
  payment_proof_url        text,
  payment_amount           numeric(10,2),
  payment_verified_at      timestamptz,
  payment_verified_by      uuid          REFERENCES public.admins(id),
  payment_rejection_reason text,
  total_amount             numeric(10,2) NOT NULL DEFAULT 0,
  -- Idempotency flag — mirrors RTDB productQtyDeducted design
  product_qty_deducted     boolean       NOT NULL DEFAULT false,
  ready_for_pickup_at      timestamptz,
  pickup_reminder_sent     boolean       NOT NULL DEFAULT false,
  pickup_reminder_sent_at  timestamptz,
  picked_up_at             timestamptz,
  picked_up_by             text,
  order_reference          text          UNIQUE,
  created_at               timestamptz   NOT NULL DEFAULT now(),
  updated_at               timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_status     ON public.orders(order_status);
CREATE INDEX idx_orders_customer   ON public.orders(customer_id);
CREATE INDEX idx_orders_created    ON public.orders(created_at DESC);
-- Partial index speeds up lookup of orders pending stock deduction
CREATE INDEX idx_orders_undeducted ON public.orders(product_qty_deducted)
  WHERE product_qty_deducted = false;

-- ── Server-side order reference generator ────────────────────────────────────
-- Generates HB-YYYYMMDD-XXXX where XXXX is 4 uppercase hex chars.
-- Retries up to 10 times on the rare UUID collision.
CREATE OR REPLACE FUNCTION public.generate_order_reference()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_ref      text;
  v_attempts integer := 0;
BEGIN
  LOOP
    v_ref := 'HB-'
      || to_char(now(), 'YYYYMMDD') || '-'
      || upper(substr(md5(gen_random_uuid()::text), 1, 4));
    BEGIN
      NEW.order_reference := v_ref;
      RETURN NEW;
    EXCEPTION WHEN unique_violation THEN
      v_attempts := v_attempts + 1;
      IF v_attempts > 10 THEN
        RAISE EXCEPTION
          'generate_order_reference: failed to generate unique ref after 10 attempts';
      END IF;
    END;
  END LOOP;
END;
$$;

CREATE TRIGGER set_order_reference
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  WHEN (NEW.order_reference IS NULL)
  EXECUTE FUNCTION public.generate_order_reference();

-- RLS
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY "orders_read_admin"     ON public.orders FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "orders_update_coadmin" ON public.orders FOR UPDATE
  USING (public.get_admin_role() = 'co_admin');
-- Customers read their own orders via stable auth_uid → customers.id link (D-G)
CREATE POLICY "orders_read_customer"  ON public.orders FOR SELECT
  USING (
    NOT public.is_active_admin()
    AND auth.uid() IS NOT NULL
    AND customer_id = (
      SELECT id FROM public.customers WHERE auth_uid = auth.uid()
    )
  );
-- No customer INSERT policy — create_customer_order RPC handles all customer order creation.


-- ══════════════════════════════════════════════════════════════
-- SECTION 10 — ORDER ITEMS
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.order_items (
  id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id      uuid          NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id    uuid          NOT NULL REFERENCES public.products(id),
  variant_id    uuid          NOT NULL REFERENCES public.product_variants(id),
  product_name  text          NOT NULL,
  bottle_size   text          NOT NULL,
  unit_price    numeric(10,2) NOT NULL,
  quantity      integer       NOT NULL CHECK (quantity > 0),
  subtotal      numeric(10,2) NOT NULL,
  created_at    timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_order_items_order_id   ON public.order_items(order_id);
CREATE INDEX idx_order_items_variant_id ON public.order_items(variant_id);

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items_read_admin"    ON public.order_items FOR SELECT
  USING (public.is_active_admin());
-- Co_admin inserts items when creating manual/wholesale orders via Admin Web
CREATE POLICY "order_items_insert_coadmin" ON public.order_items FOR INSERT
  WITH CHECK (public.get_admin_role() = 'co_admin');
-- Customers read items belonging to their own orders (UUID ownership, D-G)
CREATE POLICY "order_items_read_customer"  ON public.order_items FOR SELECT
  USING (
    NOT public.is_active_admin()
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.orders o
      JOIN  public.customers c ON c.id = o.customer_id
      WHERE o.id = order_items.order_id
        AND c.auth_uid = auth.uid()
    )
  );
-- Customers never INSERT order_items directly — only create_customer_order RPC does.


-- ══════════════════════════════════════════════════════════════
-- SECTION 11 — PRODUCTION
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.production_batches (
  id                     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id            text        UNIQUE,
  product_id             uuid        REFERENCES public.products(id),
  variant_id             uuid        REFERENCES public.product_variants(id),
  batch_name             text,
  is_bundle              boolean     NOT NULL DEFAULT false,
  status                 text        NOT NULL DEFAULT 'Planned'
                                     CHECK (status IN (
                                       'Planned', 'In Progress',
                                       'Partially Completed', 'Completed', 'Archived'
                                     )),
  qty_target             integer     NOT NULL DEFAULT 0 CHECK (qty_target >= 0),
  qty_completed          integer     NOT NULL DEFAULT 0 CHECK (qty_completed >= 0),
  -- Idempotency flag — mirrors RTDB inventoryUpdated design
  inventory_updated      boolean     NOT NULL DEFAULT false,
  inventory_added_qty    integer,
  order_id               uuid        REFERENCES public.orders(id),
  customer_name          text,
  items_summary          text,
  is_archived            boolean     NOT NULL DEFAULT false,
  created_by             uuid        REFERENCES public.admins(id),
  completed_at           timestamptz,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  -- Preserved Firebase display fields
  bottle_size            text,
  product_name           text,
  production_date        text,
  start_date             text,
  target_completion_date text
);

CREATE INDEX idx_batches_status   ON public.production_batches(status);
CREATE INDEX idx_batches_archived ON public.production_batches(is_archived)
  WHERE is_archived = false;
CREATE INDEX idx_batches_inv_upd  ON public.production_batches(inventory_updated)
  WHERE inventory_updated = false;

CREATE TABLE public.production_history (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id          text        UNIQUE,
  batch_id             uuid        NOT NULL REFERENCES public.production_batches(id),
  item_id              uuid,
  prev_completed_qty   integer     NOT NULL,
  new_completed_qty    integer     NOT NULL,
  inventory_adjustment integer     NOT NULL,
  edited_by            uuid        REFERENCES public.admins(id),
  created_at           timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.production_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.production_history  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "batches_read_admin"    ON public.production_batches FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "batches_write_coadmin" ON public.production_batches FOR ALL
  USING  (public.get_admin_role() = 'co_admin')
  WITH CHECK (public.get_admin_role() = 'co_admin');
CREATE POLICY "history_read_admin"    ON public.production_history FOR SELECT
  USING (public.is_active_admin());


-- ══════════════════════════════════════════════════════════════
-- SECTION 12 — PRODUCTION BATCH ITEMS (bundles)
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.production_batch_items (
  id              uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id        uuid    NOT NULL REFERENCES public.production_batches(id) ON DELETE CASCADE,
  product_id      uuid    REFERENCES public.products(id),
  variant_id      uuid    REFERENCES public.product_variants(id),
  product_name    text    NOT NULL,
  bottle_size     text    NOT NULL,
  qty_target      integer NOT NULL DEFAULT 0,
  qty_completed   integer NOT NULL DEFAULT 0,
  status          text    NOT NULL DEFAULT 'Pending'
);

CREATE INDEX idx_batch_items_batch_id ON public.production_batch_items(batch_id);

ALTER TABLE public.production_batch_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "batch_items_read_admin"    ON public.production_batch_items FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "batch_items_write_coadmin" ON public.production_batch_items FOR ALL
  USING  (public.get_admin_role() = 'co_admin')
  WITH CHECK (public.get_admin_role() = 'co_admin');


-- ══════════════════════════════════════════════════════════════
-- SECTION 13 — SUPPLIERS
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.suppliers (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_name    text        NOT NULL,
  contact_person   text,
  contact_number   text,
  address          text,
  supplies         text,
  last_supply_date text,
  notes            text,
  status           text        NOT NULL DEFAULT 'Active'
                               CHECK (status IN ('Active', 'Inactive')),
  created_by       uuid        REFERENCES public.admins(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "suppliers_read_admin"    ON public.suppliers FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "suppliers_write_coadmin" ON public.suppliers FOR ALL
  USING  (public.get_admin_role() = 'co_admin')
  WITH CHECK (public.get_admin_role() = 'co_admin');


-- ══════════════════════════════════════════════════════════════
-- SECTION 14 — NOTIFICATIONS
-- ══════════════════════════════════════════════════════════════
--
-- Notification types used by database_service.dart (verified from source):
--   OUT_OF_STOCK, LOW_STOCK          — warehouse inventory
--   PRODUCTION_COMPLETED             — production
--   NEW_SALE                         — order completed
--   PAYMENT_VERIFIED, PAYMENT_REJECTED
--   SCAN_MISMATCH                    — IoT scan (written to Firebase, bridge copies here)
--   BOTTLE_LOW_STOCK                 — IoT bottle-size threshold
--   PICKUP_REMINDER_SENT             — pickup reminder
--   ORDER_PICKED_UP                  — QR scanner
--
-- New types added by Supabase RPC (R2):
--   STOREFRONT_OUT_OF_STOCK          — product_qty reached 0 via complete_order
--   STOREFRONT_LOW_STOCK             — product_qty at or below reorder_level via complete_order
--
-- Note: STOREFRONT_* prefix distinguishes storefront stock from warehouse stock,
-- avoiding confusion in the Notifications page in the Admin Web.
-- The existing Flutter NotificationsPage displays notifications by message text,
-- not by type — so the new types do not require a Flutter change.
--

CREATE TABLE public.notifications (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  type        text        NOT NULL,
  message     text        NOT NULL,
  related_id  text,
  is_read     boolean     NOT NULL DEFAULT false,
  is_archived boolean     NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_unread  ON public.notifications(is_read)
  WHERE is_read = false;
CREATE INDEX idx_notifications_created ON public.notifications(created_at DESC);
-- Deduplication index: prevents duplicate unread notifications of the same type
-- for the same related_id.
-- IMPORTANT: PostgreSQL does not treat NULL as equal in unique indexes.
-- If related_id is NULL, two rows with the same type can coexist (NULL != NULL).
-- All current RPC callers pass non-NULL related_id values, so this is not
-- a problem in practice. Future callers must also pass non-NULL related_id
-- for deduplication to work.
CREATE UNIQUE INDEX idx_notifications_dedup ON public.notifications(type, related_id)
  WHERE is_read = false;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications_read_admin"   ON public.notifications FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "notifications_update_admin" ON public.notifications FOR UPDATE
  USING (public.is_active_admin());

-- Clients cannot create or delete notifications.
REVOKE INSERT, DELETE ON public.notifications FROM authenticated, anon;


-- ══════════════════════════════════════════════════════════════
-- SECTION 15 — CONVERSATIONS & MESSAGES
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.conversations (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id     uuid        REFERENCES public.customers(id),
  customer_name   text        NOT NULL,
  customer_email  text        NOT NULL,  -- contact info only
  order_id        uuid        REFERENCES public.orders(id),
  status          text        NOT NULL DEFAULT 'open'
                              CHECK (status IN ('open', 'resolved')),
  last_message    text,
  is_read         boolean     NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Prevents duplicate open conversations for same customer + order.
-- Replaces the O(n) full-scan dedup in current createConversation().
CREATE UNIQUE INDEX idx_conv_dedup
  ON public.conversations(customer_email, COALESCE(order_id::text, 'none'))
  WHERE status != 'resolved';

CREATE TABLE public.messages (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  message         text        NOT NULL,
  sender_id       text,
  sender_role     text        NOT NULL DEFAULT 'co_admin',
  sender_name     text,
  is_read         boolean     NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_conv_id ON public.messages(conversation_id);
CREATE INDEX idx_messages_created ON public.messages(created_at ASC);

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages       ENABLE ROW LEVEL SECURITY;

-- Admin access
CREATE POLICY "convs_read_admin"    ON public.conversations FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "convs_write_coadmin" ON public.conversations FOR ALL
  USING  (public.get_admin_role() = 'co_admin')
  WITH CHECK (public.get_admin_role() = 'co_admin');

-- Stage 1: co_admin only for messages
CREATE POLICY "msgs_read_admin"    ON public.messages FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "msgs_write_coadmin" ON public.messages FOR INSERT
  WITH CHECK (public.get_admin_role() = 'co_admin');

-- Stage 2 customer policies (documented for future implementation):
-- Customer read: conversations where customer_id → customers.auth_uid = auth.uid()
-- Customer message: via create_customer_message RPC only (not direct INSERT)
-- Customers cannot initiate new conversations (D-F).


-- ══════════════════════════════════════════════════════════════
-- SECTION 16 — FEEDBACK
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.feedback (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id     uuid        REFERENCES public.customers(id),
  customer_name   text        NOT NULL,
  customer_email  text,
  rating          integer     CHECK (rating BETWEEN 1 AND 5),
  message         text        NOT NULL,
  order_id        uuid        REFERENCES public.orders(id),
  product_name    text,
  admin_reply     text,
  replied_at      timestamptz,
  replied_by      uuid        REFERENCES public.admins(id),
  is_read         boolean     NOT NULL DEFAULT false,
  is_archived     boolean     NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "feedback_read_admin"     ON public.feedback FOR SELECT
  USING (public.is_active_admin());
CREATE POLICY "feedback_update_coadmin" ON public.feedback FOR UPDATE
  USING (public.get_admin_role() = 'co_admin');
-- Authenticated customers only (D-C); email and order ownership enforced
CREATE POLICY "feedback_insert_customer" ON public.feedback FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND NOT public.is_active_admin()
    AND customer_email = (auth.jwt() ->> 'email')
    AND (
      order_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.orders o
        JOIN  public.customers c ON c.id = o.customer_id
        WHERE o.id = feedback.order_id
          AND c.auth_uid = auth.uid()
      )
    )
  );


-- ══════════════════════════════════════════════════════════════
-- SECTION 17 — ADMIN ACTIVITY LOGS
-- ══════════════════════════════════════════════════════════════

CREATE TABLE public.admin_activity_logs (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id text        UNIQUE, -- Firebase push key for migrated records
  admin_id    uuid        REFERENCES public.admins(id),
  action      text        NOT NULL,
  details     text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_activity_admin_id ON public.admin_activity_logs(admin_id);
CREATE INDEX idx_activity_created  ON public.admin_activity_logs(created_at DESC);

ALTER TABLE public.admin_activity_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "activity_read_admin" ON public.admin_activity_logs FOR SELECT
  USING (public.is_active_admin());

-- Clients cannot write to the audit trail.
REVOKE INSERT, UPDATE, DELETE ON public.admin_activity_logs FROM authenticated, anon;
