# Honeybee Center — Firebase-to-Supabase Migration Status

**Target Supabase Project:** `honeybee-center-main`  
**Project Reference:** `gvteqrtvpfujfrwrdohv`  
**Region:** `ap-northeast-2` (Seoul)  
**Supabase URL:** `https://gvteqrtvpfujfrwrdohv.supabase.co`  
**Last Updated:** 2026-10-15  

> **Historical snapshot:** The stage tracker below predates the completed push of migrations 04–07 and the current Admin data-readiness review. Use [ADMIN_DATA_CUTOVER_READINESS.md](./ADMIN_DATA_CUTOVER_READINESS.md) for the verified current state and next steps.

---

## Migration Stage Tracker

| Stage | Name | Status | Validation Evidence | Next Action |
| :--- | :--- | :--- | :--- | :--- |
| **Stage 1** | Connection & Configuration | **COMPLETED** | CLI linked to `gvteqrtvpfujfrwrdohv`; `lib/config/supabase_config.dart` created; `OtpService._functionUrl` updated to target `gvteqrtvpfujfrwrdohv`. | Verify harmless read in Flutter client. |
| **Stage 2** | Database Preparation | **COMPLETED** | 19 public tables verified; 6 base RPCs verified; migration `20261015000002_rpc_fixes.sql` successfully pushed and applied on remote DB. | Proceed to Stage 5/6. |
| **Stage 3** | Backup & Data Migration | **COMPLETED** | Live verified: 4 products, 23 variants, 23 inventory rows (150 total warehouse units, 0 storefront units), 4 batches, 6 movements, 6 logs, 16 notifications seeded. | Catalog and historical data synchronized. |
| **Stage 4** | Authentication & Admin Accounts | **COMPLETED** | Live verified: Main Admin `reylbanocnoc@gmail.com` (`4eca1bad-16a6-4256-a7bd-ce41f2965a27`) and Co-Admin `coadmin67@gmail.com` (`0f286663-8d72-4ed2-84fe-2b3c347070ca`) linked in `public.admins` with active status. **Phase 2 Complete:** `AuthService` migrated from Firebase Auth to Supabase Auth with status verification and role routing. | Admin authorization fully operational on Supabase Auth. |
| **Stage 5** | Forgot Password OTP | **IN PROGRESS — LOCAL OUTBOX DRAFT, NOT READY FOR CONTROLLED REMOTE TESTING** | Request path durably enqueues encrypted requests without account lookup or SMTP; eligible and ineligible valid-format inputs receive generic HTTP 202 after commit. The Node worker asynchronously checks admin/Auth eligibility and sends encrypted jobs. Draft migration uses database time for 30-second cooldown/five-minute expiry; enforces max five OTP generations and max five SMTP attempt reservations per email hash in each rolling 60-minute window, plus five failed verification attempts per issued OTP. Attempts are reserved transactionally before SMTP, so worker crashes before a send conservatively consume a reservation. Issuance now returns `DELIVERY_PENDING` without changing the OTP or job if an SMTP lease is active; claim/issuance lock outbox rows before session rows, and eligible expired leases remain reclaimable. Node worker unit tests: 13 passed; focused Flutter tests: 20 passed; targeted Dart analysis: clean; worker `.mjs` syntax checks: passed. The Edge Function TypeScript syntax check via `node --check` is not applicable and failed on TypeScript syntax; Deno is unavailable. `supabase db lint --local` could not connect to PostgreSQL at `127.0.0.1:54322`; SQL catalog, behavior, and concurrency tests remain unrun. No SMTP, live Supabase, or end-to-end test was performed. | Start an isolated local Supabase/PostgreSQL runtime and execute the schema/behavior SQL tests plus two-session concurrency scenarios; obtain Deno type/runtime validation; configure a durable worker host and ingress WAF/API-gateway IP/global rate limiter based on trusted connection metadata; review secret names and test SMTP only in an explicitly approved controlled phase. Then seek separate approval to apply `20261015000006_otp_security_rpcs.sql`, deploy Edge Function `otp`, and start the worker. |
| **Stage 6** | Flutter Modules | **IN PROGRESS** | **Steps 6.1–6.3 Complete. Step 6.4 implemented locally:** orders and pickup use Supabase; migration `20261015000005_confirm_order_pickup.sql` defines atomic Co-Admin validation, storefront deduction, and pickup audit. Migration `20261015000004_orders_grants.sql` is present locally, but its remote migration-history status is not documented. No live Step 6.4 verification is recorded. | Check remote migration history for `20261015000004_orders_grants.sql` (apply only if absent and approved); separately obtain approval before applying `20261015000005_confirm_order_pickup.sql`; then perform live Co-Admin/order/pickup verification. |
| **Stage 7** | End-to-End Validation | **NOT STARTED** | Pending module migration. | Verify dual-role access, inventory rules, and QR pickup. |
| **Stage 8** | Production Cutover | **NOT STARTED** | Pending Stage 7 completion. | Prepare cutover checklist and obtain explicit approval. |
| **Stage 9** | Firebase Retirement | **NOT STARTED** | ESP32-CAM Firebase RTDB integration preserved. | Keep RTDB active for ESP32-CAM scan commands and results. |

---

## Active Architecture Invariants

1. **Dual Backend Coexistence:**  
   * **Supabase** is the authoritative backend for business data: authentication, products, warehouse inventory, customer orders, production batches, reports, and administrative management.
   * **Firebase Realtime Database** remains active and authoritative for ESP32-CAM IoT communications: `/scan_commands` and `/scan_results`.
2. **ESP32-CAM Scan Rule:**  
   IoT camera bottle detection (250g, 500g, 1kg) is strictly **verification-only**. It never automatically modifies Supabase inventory pools.
3. **Dual Pool Separation:**  
   Storefront product quantities and warehouse bulk inventory pools remain strictly separated. Deductions occur only at validated completion stages.
4. **Role Boundary:**  
   Main Admin retains owner monitoring and account management; Co-Admin retains operational day-to-day access.

## Outstanding Remote Changes and Blockers

No remote SQL migration or Edge Function deployment was performed for this review.

| Remote item | Local object | Remote status / action |
| :--- | :--- | :--- |
| Orders table grants | `20261015000004_orders_grants.sql` | Application status is not evidenced in the local migration log. Check remote migration history; apply only if absent and approved. |
| QR pickup RPC | `20261015000005_confirm_order_pickup.sql` / `public.confirm_order_pickup(uuid, text)` | Not applied per the local migration record; requires separate approval before application. |
| OTP security schema and RPCs | `20261015000006_otp_security_rpcs.sql` / request intake, worker leases, OTP issue/delivery, verification, reset-token claim and invalidation RPCs | Local draft only; not applied; requires PostgreSQL validation and separate approval. |
| OTP Edge Function | `supabase/functions/otp/index.ts` / function name `otp` | Local draft only; not deployed; requires separate approval. |
| OTP outbox worker | `supabase/workers/otp/worker.mjs` | Local Node worker only; no host/scheduler has been configured or verified. Do not run against production without separately approved secrets, deployment, and testing. |

Stage 5 local validation does not establish SQL/runtime correctness or live functionality. `supabase db lint --local` could not connect to PostgreSQL at `127.0.0.1:54322`; PostgreSQL migration and concurrency tests therefore have not run. Deno is unavailable, so Edge Function Deno type/runtime validation has not run (Node TypeScript stripping verified module parsing only). No Supabase, Auth Admin, worker-host, or SMTP integration test was performed. The HTTP request path performs only validation, salted address hashing, encryption, and a durable insert, so account eligibility is not an HTTP response or lookup-timing input. This substantially reduces account-enumeration timing differences, but cannot guarantee identical network/database response times under different load or failure conditions.

The Edge Function requires these server-side secret names: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `OTP_SALT_SECRET`, and `OTP_OUTBOX_ENCRYPTION_KEY`. The standalone worker additionally requires `SMTP_USER` and `SMTP_PASS`. Presence/configuration is unverified; no values were inspected or changed. A worker host and public-ingress global/IP rate limit are not configured. Without trusted ingress limiting, an attacker can create queue-storage load using many distinct email hashes; do not trust client-supplied IP headers. A WAF/API gateway must derive IP from the connection and strip/overwrite forwarded headers. PostgreSQL separately caps OTP generations and reserved SMTP attempts at five per rolling hour per email hash. SMTP acceptance followed by a worker crash can result in duplicate delivery of the same OTP, not exactly-once delivery. These are blockers to controlled remote testing.
