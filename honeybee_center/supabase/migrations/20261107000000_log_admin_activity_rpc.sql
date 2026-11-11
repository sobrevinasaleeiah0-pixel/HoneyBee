BEGIN;

-- ══════════════════════════════════════════════════════════════
-- log_admin_activity RPC
--
-- Provides a SECURITY DEFINER write path into
-- public.admin_activity_logs for authenticated, active
-- administrators (both main_admin and co_admin).
--
-- Background:
--   The table's REVOKE INSERT, UPDATE, DELETE FROM authenticated, anon
--   (schema.sql §17) means no client can write directly via REST or SDK.
--   This RPC is the ONLY permitted write path from the application layer.
--
-- Security properties:
--   • SET search_path = '' — empty search_path; every referenced
--     object is fully schema-qualified. Eliminates all shadow-schema
--     injection risk regardless of session-level search_path.
--   • Requires public.is_active_admin() — rejects anon, service_role,
--     and inactive admins. Accepts active main_admin and co_admin.
--   • Uses auth.uid() exclusively as admin_id — never accepts a
--     caller-supplied ID parameter.
--   • Validates p_action (non-null, non-blank) and clamps both
--     inputs before INSERT to bound storage.
--   • REVOKE ALL … FROM PUBLIC, anon before GRANT to authenticated
--     follows the project-wide pattern for admin-facing RPCs.
--
-- Column mapping (public.admin_activity_logs):
--   id          → DEFAULT gen_random_uuid()   (not supplied)
--   external_id → NULL                        (reserved for Firebase backfill)
--   admin_id    → auth.uid()                  (Supabase JWT; not caller-supplied)
--   action      → left(btrim(p_action), 200)  (trimmed and clamped)
--   details     → left(p_details, 2000)       (NULL permitted)
--   created_at  → DEFAULT now()               (not supplied)
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.log_admin_activity(
  p_action  text,
  p_details text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
BEGIN
  -- Require an active administrator (main_admin or co_admin).
  -- public.is_active_admin() returns false for anon, service_role,
  -- and any admin whose status != 'active'.
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'log_admin_activity: active admin role required';
  END IF;

  -- Reject null or blank action before hitting the NOT NULL constraint
  -- so callers receive a descriptive error rather than a raw violation.
  IF p_action IS NULL OR pg_catalog.btrim(p_action) = '' THEN
    RAISE EXCEPTION 'log_admin_activity: p_action must not be null or empty';
  END IF;

  -- Insert the activity record.
  -- admin_id is always auth.uid() — the Supabase JWT claim.
  -- external_id is intentionally omitted (NULL) for Supabase-native rows;
  -- it is reserved for future Firebase historical backfill only.
  INSERT INTO public.admin_activity_logs (admin_id, action, details)
  VALUES (
    auth.uid(),
    pg_catalog.left(pg_catalog.btrim(p_action), 200),
    pg_catalog.left(p_details, 2000)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Transfer ownership to the database superuser so the function
-- executes as postgres (required for SECURITY DEFINER to bypass
-- the REVOKE INSERT on public.admin_activity_logs).
ALTER FUNCTION public.log_admin_activity(text, text)
  OWNER TO postgres;

-- Revoke the default PUBLIC execute privilege (and deny anon
-- explicitly), then grant only to authenticated callers.
-- public.is_active_admin() inside the function further restricts
-- this to active main_admin and co_admin rows only.
REVOKE ALL ON FUNCTION public.log_admin_activity(text, text)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.log_admin_activity(text, text)
  TO authenticated;

COMMIT;
