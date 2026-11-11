-- ============================================================
-- Honeybee Center — 003 Admin Provisioning
-- Location: supabase/provisioning/20261015000002_provisioning.sql
-- Target:   honeybee-center-main (gvteqrtvpfujfrwrdohv)
-- Applied:  Phase 0b — AFTER Phase 0a (schema migration) is complete
--
-- !! DO NOT run via `supabase db push` !!
-- This file is NOT in migrations/ and will not be tracked.
-- Run it manually via the Supabase Dashboard SQL Editor ONLY.
--
-- WHAT THIS SCRIPT DOES:
--   Inserts the initial main_admin row into public.admins.
--   The trigger's empty-table bootstrap window allows this INSERT
--   only when the admins table is empty and role = 'main_admin'.
--   The bootstrap window closes permanently once this row is committed.
--
-- WHAT THIS SCRIPT DOES NOT DO:
--   It does not create the Co-Admin account. The co_admin is provisioned
--   through the Admin Web panel after the main_admin logs in (Phase 1).
--
-- OBTAINING THE UUID:
--   The UUID must be the Supabase Auth user ID of the main_admin account.
--   There are two safe ways to get it:
--
--   Option A — Invite API (creates the Auth account and returns the UUID):
--     POST https://gvteqrtvpfujfrwrdohv.supabase.co/auth/v1/admin/users
--     Authorization: Bearer <service_role_key>
--     Content-Type: application/json
--     Body: { "email": "honeybeecenter67@gmail.com", "invite": true }
--     → Response contains "id": "<uuid>". That is MAIN_ADMIN_UUID.
--     → The invitation email is sent automatically.
--
--   Option B — Dashboard Users page (if the account already exists):
--     Supabase Dashboard → Authentication → Users
--     Find honeybeecenter67@gmail.com and copy the UUID shown there.
--
--   Do not guess or invent a UUID. The UUID must match the Supabase Auth
--   record or the account will not be able to log in.
--
-- INSTRUCTIONS:
--   1. Create the main_admin Supabase Auth account (Option A above),
--      OR verify it exists in the Users page (Option B).
--   2. Copy the UUID from the API response or the Dashboard Users page.
--   3. Replace <MAIN_ADMIN_UUID> below with the actual UUID.
--   4. Open Supabase Dashboard → SQL Editor for honeybee-center-main.
--   5. Paste this file's contents and click Run.
--   6. Run the verification query at the bottom and confirm 1 row.
--
-- BUILT-IN SAFETY:
--   '<MAIN_ADMIN_UUID>' is not a valid PostgreSQL uuid literal.
--   If this file is run with an unreplaced placeholder, PostgreSQL
--   will immediately raise:
--     ERROR: invalid input syntax for type uuid: "<MAIN_ADMIN_UUID>"
--   The entire transaction rolls back. No rows are written.
-- ============================================================

BEGIN;

INSERT INTO public.admins (id, name, email, role, status, created_at)
VALUES
  (
    '4eca1bad-16a6-4256-a7bd-ce41f2965a27'::uuid,
    'Honeybee Center Admin',
    'honeybeecenter67@gmail.com',
    'main_admin',
    'active',
    now()
  );

COMMIT;

-- ── Verification query (run separately after COMMIT) ─────────────────────────
SELECT id, name, email, role, status, created_at
  FROM public.admins
 ORDER BY role;

-- Expected result (1 row):
--   <uuid> | Honeybee Center Admin | honeybeecenter67@gmail.com | main_admin | active
--
-- The co_admin account is NOT created here.
-- It will be added via the Admin Web panel during Phase 1.
