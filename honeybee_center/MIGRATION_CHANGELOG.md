# Honeybee Center — Migration Changelog

All meaningful changes, schema migrations, function updates, and configuration adjustments are recorded here in chronological order.

---

### [2026-10-15] — Phase 0a: Supabase Foundation & RPC Application
* **Status:** VERIFIED & APPLIED
* **Target:** `honeybee-center-main` (`gvteqrtvpfujfrwrdohv`)
* **Files Applied:**
  * `supabase/migrations/20261015000000_schema.sql`: Created 19 core tables, foreign keys, check constraints, RLS policies, and `prevent_role_escalation()` trigger.
  * `supabase/migrations/20261015000001_rpc_functions.sql`: Created 6 atomic, concurrency-safe RPC functions with pessimistic locking:
    1. `public.complete_order`
    2. `public.complete_production`
    3. `public.replenish_product_qty`
    4. `public.adjust_inventory`
    5. `public.create_customer_order`
    6. `public.request_otp_session`
* **Verification Evidence:** `supabase migration list` confirms both migrations are synchronized on the remote database.

---

### [2026-10-15] — Phase 0b & 0c: Main Admin Provisioning
* **Status:** VERIFIED & APPLIED
* **Target:** `honeybee-center-main` (`gvteqrtvpfujfrwrdohv`)
* **Action:**
  * Initialized Main Admin in Supabase Auth (`honeybeecenter67@gmail.com`).
  * Provisioned matching row in `public.admins` (`role: 'main_admin'`, `status: 'active'`).
* **Verification Evidence:** `supabase inspect db table-stats --linked` reports `public.admins` has `estimated_row_count: 1`.

---

### [2026-10-13] — Stage 1 & Edge Function Code Audit
* **Status:** VERIFIED (Audit & Diagnosis)
* **Environment Fix:**
  * Diagnosed IDE telemetry plugin hook blocker (`MODULE_NOT_FOUND` on Node.js due to escaped quotes in path). Fixed by user to restore tool execution.
* **Database Verification:**
  * Verified 19 tables in `public` schema via live `supabase inspect db table-stats --linked`:
    `admins`, `orders`, `product_variants`, `inventory_movements`, `production_batches`, `customers`, `admin_activity_logs`, `notifications`, `order_items`, `messages`, `production_batch_items`, `products`, `production_history`, `conversations`, `inventory`, `feedback`, `password_reset_sessions`, `suppliers`, `otp_sessions`.
* **Configuration & File Changes:**
  * Created `lib/config/supabase_config.dart` providing centralized parameters for `https://gvteqrtvpfujfrwrdohv.supabase.co`.
  * Updated `lib/services/otp_service.dart` line 49 from `vlpdexrzupyiscsntyce` to `gvteqrtvpfujfrwrdohv`.
  * Patched `supabase/functions/otp/index.ts`: Closed `requestOtp()` function and try-catch blocks cleanly, added `genericOtpResponse(req)` on success, and sanitized SMTP errors into generic failure messages.
  * Initialized `MIGRATION_STATUS.md`, `MIGRATION_CHANGELOG.md`, and `MIGRATION_GUIDE.md` in the project root.

---

### [2026-10-13] — Admin Account Alignment & RPC Fixes Migration
* **Status:** APPLIED & VERIFIED
* **Account Alignment:**
  * Target identities confirmed: Main Admin `reylbanocnoc@gmail.com` (`4eca1bad-16a6-4256-a7bd-ce41f2965a27`), Co-Admin `coadmin67@gmail.com` (`0f286663-8d72-4ed2-84fe-2b3c347070ca`).
  * Both linked in `public.admins` with active status.
* **Remote Migrations & Seed Applied:**
  * Applied `20261015000002_rpc_fixes.sql` via `supabase db push` (hardening `complete_order`, `complete_production`, `adjust_inventory`).
  * Ingested historical seed data:
    * Products: 4 rows
    * Product Variants: 23 rows (0 storefront units)
    * Warehouse Inventory: 23 rows (150 total units verified)
    * Production Batches: 4 completed batches
    * Inventory Movements: 6 audit movements
    * Admin Activity Logs: 6 logs
    * Notifications: 16 unique notifications (deduplicated)

---

### [2026-10-13] — Stage 6: Step 6.1 Read-Only Supabase Product & Inventory Reader
* **Status:** IMPLEMENTED & TESTED (Awaiting approval for Step 6.2)
* **Components Added:**
  * `lib/services/supabase_data_service.dart`: Read-only data access service with pure mapping functions (`mapSupabaseProducts`, `mapSupabaseInventory`) and reactive `BehaviorSubject` streams.
  * `test/supabase_data_service_test.dart`: Complete mapping and invariant test suite verifying:
    * 4 products and 23 variants mapped to nested Map format matching `products_page.dart` and `inventory_page.dart`.
    * Storefront stock strictly preserved at 0.
    * Warehouse stock strictly preserved at 150 bottles across 23 variant rows.
    * Dual-pool separation invariant strictly enforced.
* **Test & Analysis Verification:**
  * `flutter test test/supabase_data_service_test.dart`: All 3 tests passed (100% success rate).
  * `flutter analyze lib/services/supabase_data_service.dart test/supabase_data_service_test.dart`: 0 issues found.
* **Database Invariance:** Zero remote database writes, zero RPC calls executed, and zero schema mutations.

---

### [2026-10-13] — Phase 2: Admin Web Authentication Migration to Supabase Auth
* **Status:** IMPLEMENTED & LOCALLY VERIFIED
* **Scope Completed:**
  * Migrated `lib/services/auth_service.dart` from Firebase Auth to Supabase Auth for admin login, logout, and session restoration.
  * Verified matching `public.admins` record with active status requirement (`status = 'active'`).
  * Enforced role-based routing (Main Admin &rarr; `owner_panel.dart`; Co-Admin &rarr; `main_dashboard.dart`).
  * Maintained full backward compatibility for `AuthSession` and validator utilities.
  * Preserved Firebase Realtime Database initialization in `lib/main.dart` for ESP32-CAM `/scan_commands` and `/scan_results`.
* **Verification & Security Findings:**
  * Direct PostgREST SELECT on `public.admins` returns `42501 permission denied` because table-level `SELECT` grant is pending on `public.admins` for `authenticated`.
  * Verified `get_admin_role()` `SECURITY DEFINER` fallback behavior: returns SQL `NULL` for unauthenticated/anon callers and inactive admins, correctly rejecting unauthorized access.
  * Table-grants migration `20261015000003_table_grants.sql` is prepared locally to grant narrow `SELECT` on `admins`, `inventory`, `products`, and `product_variants`.
* **Testing & Analysis:**
  * Flutter Web build: Compilation succeeded (`build/web/main.dart.js`, 3.89 MB).
  * `flutter test test/auth_service_test.dart test/supabase_data_service_test.dart`: 9/9 tests passed (100%).
  * `flutter analyze lib/services/auth_service.dart lib/services/supabase_data_service.dart test/auth_service_test.dart test/supabase_data_service_test.dart`: 0 issues found.
* **Database Invariance:** Zero remote schema migrations, zero remote data mutations, zero password resets, and zero account changes.

---

### [2026-10-13] — Stage 6: Step 6.2 Products Page Supabase Integration
* **Status:** APPLIED & VERIFIED
* **Target:** `honeybee-center-main` (`gvteqrtvpfujfrwrdohv`)
* **Remote Migration Applied:**
  * `supabase/migrations/20261015000003_table_grants.sql` applied cleanly via `supabase db push`.
  * Verified live permissions: `products` and `product_variants` (23 rows) accessible to `anon`/`authenticated`; `inventory` and `admins` restricted and protected by RLS.
* **Flutter UI Integration:**
  * `lib/pages/products_page.dart`: Converted from Firebase RTDB event streams to `SupabaseDataService` reactive streams (`productsStream` and `inventoryStream`).
  * Preserved full UI styling, product IDs, variant sorting by size (`_sizeToGrams`), price, product quantity, status badges, and action controls.
  * Added on-demand refresh button in header for explicit Supabase catalog re-sync.
  * Preserved dual-pool stock separation: storefront stock (`product_qty`) vs warehouse stock (`inventory.quantity`).
* **Verification & Testing:**
  * `flutter test test/auth_service_test.dart test/supabase_data_service_test.dart`: 9/9 tests passed (100%).
  * `flutter analyze lib/pages/products_page.dart lib/services/supabase_data_service.dart`: 0 issues found.
  * `flutter build web`: Web compilation verified.

---

### [2026-10-13] — Stage 6: Step 6.3 Inventory Page Supabase Integration
* **Status:** IMPLEMENTED & VERIFIED
* **Target:** `honeybee-center-main` (`gvteqrtvpfujfrwrdohv`)
* **Flutter UI & Service Integration:**
  * `lib/services/supabase_data_service.dart`: Added `adjustInventory()` method calling secured `adjust_inventory` RPC with pessimistic locking and movement audit logging.
  * `lib/pages/inventory_page.dart`:
    * Overview KPI Header: Replaced Firebase streams with `_supabaseData.productsStream` and `_supabaseData.inventoryStream`. Added refresh button.
    * Overview Tab: Wired inventory table rows directly to live Supabase warehouse inventory (23 variant rows, 150 total units).
    * Bottle Sizes Tab: Derived variant rows and stock levels from Supabase catalog and warehouse inventory streams.
    * Verification Tab: Preserved ESP32-CAM Firebase RTDB scan commands (`/scan_commands`) and results (`/scan_results`). Derived size list from Supabase catalog.
    * Stock Corrections Tab: Added Co-Admin role validation (Main Admin is monitoring-focused). Wired corrections to call Supabase `adjust_inventory` RPC with dual-write to Firebase RTDB for backward compatibility.
  * Preserved dual-pool stock separation invariant: bulk warehouse units (`inventory.quantity`) vs storefront units (`product_qty`).
* **Verification & Testing:**
  * `flutter test test/auth_service_test.dart test/supabase_data_service_test.dart`: 9/9 tests passed (100%).
  * `flutter analyze`: Clean on all updated business logic.
  * `flutter build web`: Web compilation verified.

---

### [2026-10-13] — Stage 6: Step 6.4 Orders & QR Pickup Integration
* **Status:** IMPLEMENTED LOCALLY; REMOTE MIGRATION NOT APPLIED
* **Flutter Changes:**
  * `lib/services/supabase_data_service.dart`: QR lookup now matches an exact normalized Supabase order reference. Added pickup eligibility checks for payment, Ready-for-Pickup status, cancellation, and prior processing. Pickup calls `confirm_order_pickup`.
  * `lib/pages/pickup_qr_scanner_page.dart`: Removed Firebase order fallback, demo order, and Firebase order/notification writes. QR pickup is Co-Admin-only and reports failed Supabase lookups instead of treating them as valid fallback orders.
  * `lib/pages/orders_page.dart`: Payment verification and rejection updates are written to Supabase only; Supabase continues recording verification time, verifying admin, and rejection reason.
  * Storefront `product_qty` remains separate from warehouse `inventory.quantity`. Existing ESP32-CAM Firebase RTDB scan paths and dependencies are unchanged.
* **Local Migration Prepared:**
  * `supabase/migrations/20261015000005_confirm_order_pickup.sql` defines a Co-Admin-only transaction that locks the order, validates the exact reference, payment status, pickup readiness, and idempotency, calls `complete_order`, and records `picked_up_at` / the authenticated active admin’s name. Failures roll back both stock deduction and pickup audit.
  * The migration has **not** been applied remotely. No remote schema/data, accounts, passwords, or deployment were changed.
* **Verification:**
  * `flutter test test/auth_service_test.dart test/supabase_data_service_test.dart`: 12/12 passed.
  * Targeted `flutter analyze` on the modified Dart files: no issues found.
  * Full `flutter analyze`: 99 project-wide info-level findings; no warnings or errors. The changed Dart files analyze cleanly.
  * `flutter build web`: succeeded. The optional Wasm dry run reports the existing `dart:html` import in `reports_page.dart`; standard Web output was built successfully.
  * Full `flutter test` was attempted; the existing `test/widget_test.dart` cannot compile on the VM because `reports_page.dart` imports `dart:html`. The focused auth and Supabase service tests pass.
  * Live pickup/RPC behavior is not verified because the migration was not applied.

---

### [2026-10-13] — Stage 5: Supabase OTP Reset Review
* **Status:** PREPARED LOCALLY; NOT APPLIED OR DEPLOYED
* **Implementation:**
  * Reviewed `supabase/migrations/20261015000006_otp_security_rpcs.sql`, `supabase/functions/otp/index.ts`, and the Flutter client as one request/verification/reset flow. The RPC names, parameter names, scalar results, and JSON response fields align with the client.
  * Fixed the Edge Function OPTIONS handler to return a bodyless HTTP 204 response.
  * Updated the OTP migration draft to cap resend timestamps at 30 seconds and retain OTP rows after verification/expiry so completing or aging out an OTP cannot reset the five-sends-per-hour counter. Successful verification now invalidates the hash atomically; the per-code attempt counter remains limited to five.
  * Added service-role-only `invalidate_otp_session(email_hash, otp_hash)`. If SMTP delivery fails or the request RPC outcome is uncertain, the Edge Function conditionally invalidates only that OTP while preserving send counters and cooldown state; a late failure cannot invalidate a newer OTP. Cleanup remains best-effort if PostgreSQL is unavailable.
  * Reset-token claiming remains one-time before the Auth Admin password update. On update/network failure, cleanup is best-effort and does not make the token reusable; an uncertain update result may require a new OTP request.
  * Forgot-password request outcomes use the same generic status/body for unknown/ineligible accounts, cooldown/rate limiting, and operational failures. The UI now filters OTP input to digits.
  * The Edge Function uses Supabase Auth Admin for password updates and PostgreSQL OTP/reset state, not Firebase Auth/RTDB. Service-role credentials, OTP salt, and SMTP credentials are read only from Edge Function environment variables; none are referenced by Flutter code.
  * Aligned `OtpService` and the forgot-password UI with generic request responses and email-plus-code verification. Added the Supabase public API key headers required for Edge Function invocation.
  * Added `test/otp_service_test.dart` covering request, verification, password-reset payloads, and unsuccessful responses.
* **Local Verification:**
  * `flutter test test/otp_service_test.dart test/auth_service_test.dart test/supabase_data_service_test.dart`: 19/19 passed (7 OTP tests).
  * Targeted `flutter analyze` for the OTP service, forgot-password page, and OTP test: no issues found.
  * `node --experimental-strip-types --check supabase/functions/otp/index.ts`: passed. Deno is not installed, so this is syntax-only validation, not Deno type/runtime validation.
  * SQL migration was reviewed against the checked-in schema and prior RPC, but was not executed because local PostgreSQL tooling is unavailable.
* **Remaining Blockers:** Generic request status/body remove direct response-based enumeration, but synchronous account lookup/database/SMTP timing remains a side channel. Avoid adding artificial delays or non-durable fire-and-forget delivery; robust mitigation requires a durable mail outbox/worker with generic enqueue behavior for eligible and ineligible addresses. Cleanup after SMTP or uncertain RPC failure is conditional and best-effort; if PostgreSQL is unavailable during cleanup, a possibly undelivered code may remain usable until its five-minute expiry. Presence/configuration of `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `OTP_SALT_SECRET`, `SMTP_USER`, and `SMTP_PASS`, and actual SMTP delivery, are unverified. Deno, `psql`, and Docker were unavailable, so Deno runtime/type checks and PostgreSQL migration execution remain outstanding. The function has not been deployed and migration `20261015000006_otp_security_rpcs.sql` has not been applied. Stage 5 is not yet ready for controlled remote testing.
* **Other Pending Remote Items:** `20261015000004_orders_grants.sql` remote status is undocumented and must be checked against migration history; `20261015000005_confirm_order_pickup.sql` remains unapplied per the local migration record. No remote migration, deployment, data, password, or account change was performed.

---

### [2026-10-13] — Stage 5: Durable OTP Outbox and Worker (Local Draft)
* **Status:** IMPLEMENTED LOCALLY; NOT APPLIED, DEPLOYED, OR LIVE-TESTED
* **Architecture and security controls:**
  * Replaced the account-sensitive synchronous request path with an independent PostgreSQL inbox insert. The Edge Function validates format, applies the existing server-salted address hash, encrypts the address with AES-GCM, and returns the same generic HTTP 202 response for all valid-format addresses after the insert commits. It does not query admin eligibility or wait for SMTP. An enqueue/database failure returns a generic infrastructure 503.
  * `20261015000006_otp_security_rpcs.sql` defines RLS-protected request/outbox tables, service-role-only RPCs, row leases, `FOR UPDATE SKIP LOCKED`, per-email issue serialization, one live outbox row per email, generation-bound OTP state, single-use reset-token claims, and one-day cleanup for completed request/outbox and old reset-session rows.
  * Request intake and verification retain the existing salted email-hash format so in-flight OTP rows and hourly counters remain addressable; OTP values themselves use HMAC-SHA256. The issue RPC checks that the active admin UUID, normalized email, and allowed admin role match. PostgreSQL enforces the 30-second resend cooldown, five-minute code expiry, maximum five failed verification attempts per code, and maximum five SMTP delivery attempts per email hash per rolling hour; SMTP retries count toward the limit.
  * Added a standalone Node polling worker using the Supabase REST RPCs. SMTP retries reuse the same encrypted OTP; an SMTP-accepted message followed by a worker crash can cause duplicate mail but not multiple valid codes. A code remains pending until delivery completion is acknowledged; retry exhaustion/expiry invalidates that generation.
  * Service-role, OTP salt, outbox encryption, and SMTP credentials remain server-side. No Flutter or Firebase ESP32-CAM scan behavior was changed. Required secret names are documented without values in the worker README.
* **Local validation:**
  * `npm --prefix supabase/workers/otp test`: 13 passed, 0 failed, including AES-GCM format interoperability between Edge WebCrypto and Node.
  * `npm --prefix supabase/workers/otp audit --omit=dev`: 0 vulnerabilities.
  * Node syntax checks passed for all three `.mjs` files. Node's experimental TypeScript stripping loaded the Edge Function module successfully, but is parsing-only and is not a Deno type/runtime check.
  * `flutter test test/otp_service_test.dart test/auth_service_test.dart test/supabase_data_service_test.dart`: 20 passed, including HTTP 202 acceptance.
  * Targeted `flutter analyze lib/services/otp_service.dart lib/pages/forgot_password_page.dart test/otp_service_test.dart`: no issues found.
  * Full `flutter test`: 20 passed; `test/widget_test.dart` fails to compile on the VM because the existing `reports_page.dart` imports web-only `dart:html`. Full `flutter analyze`: 99 existing project findings (8 warnings, 91 info); targeted changed-file analysis remains clean.
  * `supabase db lint --local` was attempted but could not connect to local PostgreSQL at `127.0.0.1:54322`. The SQL contract script and manual concurrency/failure scenarios remain unexecuted.
* **Unresolved risks and blockers:** No Deno, local PostgreSQL/Supabase, live Auth Admin, SMTP, or worker-host integration test was performed. Network/load variation means exact uniform response timing cannot be guaranteed even though account eligibility is removed from the HTTP path. There is no configured global/IP ingress rate limiter, so queue storage can be abused using many distinct addresses. SMTP is at-least-once under uncertain acceptance, not exactly-once; retries can send duplicate copies of the same code, capped at five delivery attempts per address/hour. Worker hosting, secret presence/rotation policy, and actual delivery remain unconfigured/unverified. Stage 5 is not ready for controlled remote testing.
* **Remote actions still requiring separate approval:** Apply migration `20261015000006_otp_security_rpcs.sql`; deploy the `otp` Edge Function; configure its secret names (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `OTP_SALT_SECRET`, `OTP_OUTBOX_ENCRYPTION_KEY`); provision/configure and run the OTP worker with `SMTP_USER` and `SMTP_PASS`; establish ingress abuse controls; and conduct approved end-to-end testing. Separately, `20261015000004_orders_grants.sql` remote status remains undocumented and `20261015000005_confirm_order_pickup.sql` remains unapplied per the local migration record. No remote action was taken.

---

### [2026-10-15] — Stage 5: OTP Outbox Rate and Lease Hardening (Local Draft)
* **Status:** LOCAL CHANGES ONLY; SQL NOT EXECUTED; NOT APPLIED OR DEPLOYED
* **Changes:**
  * `issue_otp_email_job` no longer accepts caller-provided timestamps. PostgreSQL derives the 30-second resend cooldown and five-minute OTP/outbox expiry from database time.
  * Added `otp_email_rate_events` as a timestamped event ledger. Advisory-locked issuance enforces at most five OTP generations per normalized email hash in a rolling 60-minute window; transactional SMTP attempt reservations enforce at most five attempt claims per email hash in the same rolling window, including retries and worker crashes.
  * Hardened `claim_otp_email_jobs` cleanup so an active `sending` lease is not failed or scrubbed at the fifth-attempt or expiry boundary. Expired leases are failed/scrubbed on a later claim; only then may the matching OTP be invalidated.
  * Kept the worker RPC parameter list aligned with the six-argument issue RPC. Updated schema access assertions and rollback-only PostgreSQL behavior scenarios for database-owned time, cooldown, the active/expired fifth-attempt lease, rolling-hour counts, and expiry.
  * Updated test/deployment instructions to distinguish Node mocks from PostgreSQL behavior/concurrency checks, prohibit applying migrations 04/05 as part of the OTP rollout, document trusted ingress WAF/API-gateway rate limiting, and list required secret names without values.
* **Local validation:**
  * `npm --prefix supabase/workers/otp test`: 13 passed, 0 failed. These are in-memory worker unit tests, not SQL/PostgreSQL tests.
  * `node --check` for `worker.mjs`, `worker_core.mjs`, and `worker_crypto.mjs`: passed.
  * `flutter test test/otp_service_test.dart test/auth_service_test.dart test/supabase_data_service_test.dart`: 20 passed.
  * `flutter analyze lib/services/otp_service.dart lib/pages/forgot_password_page.dart test/otp_service_test.dart`: no issues found.
  * `supabase db lint --local`: unable to connect to local PostgreSQL at `127.0.0.1:54322`. `psql`, Docker, and Deno are unavailable. The SQL schema/behavior tests and two-session PostgreSQL concurrency scenarios have not run. An attempted `node --experimental-strip-types --check` of the Edge Function is not a valid TypeScript validation path and rejected its type annotation; no Edge Function/Deno runtime validation is claimed.
* **Remaining risks and blockers:** PostgreSQL syntax, locking, rolling-window boundaries, and SQL tests are unverified until run against isolated PostgreSQL. No reliable IP/global intake limit exists in the application; public ingress must impose one from connection-derived IP metadata and overwrite untrusted forwarding headers. SMTP is at-least-once: uncertain acceptance can duplicate the same code email. No worker host, remote secrets, SMTP, live function, or end-to-end flow was tested.
* **Remote actions still requiring separate approval:** Apply migration `20261015000006_otp_security_rpcs.sql`; deploy Edge Function `otp`; configure server-side secrets `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `OTP_SALT_SECRET`, `OTP_OUTBOX_ENCRYPTION_KEY`, `SMTP_USER`, and `SMTP_PASS`; provision and start a durable worker; configure ingress abuse controls; and perform controlled end-to-end testing. Migrations `20261015000004_orders_grants.sql` and `20261015000005_confirm_order_pickup.sql` remain outside this work and were not modified or applied.

---

### [2026-10-15] — Stage 5: Preserve Active OTP Email Leases During Issuance
* **Status:** LOCAL SQL DRAFT AND TEST CHANGES; NOT EXECUTED AGAINST POSTGRESQL
* **Changes:**
  * `issue_otp_email_job` now returns `DELIVERY_PENDING` without altering the current OTP/session or outbox payload when a matching SMTP lease is still active. Once the lease has expired, the old job may be marked stale and its encrypted payloads cleared before a new generation is created.
  * Issuance and the email-claim loop now acquire outbox row locks before session row locks. The email claim routine rechecks a selected row after locking and uses `SKIP LOCKED`, so competing workers cannot acquire the same outbox row; the active-generation cleanup keeps eligible expired leases pending for reclaim.
  * Extended rollback SQL scenarios for active-lease issuance, expiry/reclaim, supersession, and rejection of a stale worker token. Added two-session manual race procedures to `migration_tests.md`.
* **Validation:** No PostgreSQL/Supabase local runtime is available (Docker/Podman and PostgreSQL binaries absent). The SQL behavior/schema tests and concurrency procedures have not run; SQL locking semantics are therefore not claimed as verified. No linked or remote database command, migration, deployment, secret, email, or account action was performed.
