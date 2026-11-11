# Honeybee Center Admin Data Cutover Readiness

**Target Supabase project:** `honeybee-center-main` (`gvteqrtvpfujfrwrdohv`)  
**Review scope:** Read-only source, remote catalog, RLS, and privilege inspection. No application or remote changes were made for this review.

## Current verified state

- Migrations `20261015000000` through `20261015000007` are applied. The prior post-push verification confirmed the active Co-Admin `coadmin67@gmail.com` remains present.
- The Admin Flutter app initializes both Supabase and Firebase. Supabase is used for Auth/OTP and some product, inventory, order, and pickup paths; Firebase RTDB still backs multiple Admin business screens and services.
- The Customer App source is not present in this workspace. A user-shared read-only audit snapshot reports Supabase product reads and Firestore order/message writes, but its source findings have not been independently verified here.
- The remote catalog contains business tables for products/variants, inventory/movements, orders/items, production batches/items/history, suppliers, customers, admins, activity logs, notifications, conversations/messages, and feedback.
- The deployed `otp` Edge Function and a durable OTP worker host remain unverified/unavailable. OTP end-to-end delivery has not been verified; this is separate from the business-data cutover.

## Customer App findings from the shared audit snapshot

These are findings **reported by the audit text supplied from the other laptop**, not a direct review of that source tree in this workspace:

- The app reportedly reads the storefront catalog from Supabase (`products` and `product_variants`) but uses Firestore for active order writes and customer-message create/read-status flows.
- Firestore product-stream and order-stream methods were reportedly unused. Customer and admin order screens instead observe an in-memory `OrderService.orderNotifier`; the snapshot reports no durable order reload after restart or on another device.
- Guest checkout is available; login/account flows are described as prototype client-side checks with no Supabase Auth or Firebase Auth session integration.
- Checkout reportedly enters `OrderService.createOrder` from both `CheckoutPage.placeOrder` and `CheckOut.placeOrder`; each attempt creates a new `HB-...` order ID, saves the Firestore order, then updates the in-memory notifier. Firestore `saveOrder` reportedly uses `set(..., merge: true)`.
- The reported Firestore order shape includes order ID, total, payment method/name, fulfillment status, created timestamp, payment proof/reference/amount/submission/verification/rejection fields, and an embedded `items` list with product ID/name, weight, price, quantity, and subtotal. The audit says there is no customer ID/name/email/phone in the Order model/payload.
- The report identifies local order statuses `waitingPaymentVerification`, `preparing`, `readyForPickup`, `waitingPickup`, `completed`, and `cancelled`; payment verification statuses `notSubmitted`, `waitingVerification`, `verified`, and `rejected`; and payment methods `gcash`, `maya`, and `cashAtStore`. These do not automatically match the Admin app's status strings or database fields.
- Payment submission/approval/rejection reportedly writes Firestore, but the proof-upload screen is blocked and the submission method has no current screen call site. Admin completion reportedly changes order status only; it does not deduct inventory.
- The app reportedly does not deduct stock on order creation/completion and has no warehouse/storefront pool separation or replenishment transfer. Its product model treats `product_qty` as storefront stock.
- Payment-proof submission is disabled in the UI; reviews, bundle requests, profile/address data are reportedly in-memory only. No ESP32-CAM integration was found in that app audit.
- The reported Firestore retry behavior generates a new client-side order ID per attempt, so an ambiguous timeout may create duplicate orders. The app's local notifier is not a durable substitute for an order read API.

The same snapshot proposes a design (not implemented or remotely verified): retain the publishable client key; create orders and order items atomically through a narrow server-side RPC/Edge Function; derive price and totals from server-side catalog data; require a unique idempotency key; and allow guest lookup only using a high-entropy token whose verifier is stored server-side, rather than granting anonymous clients broad order SELECT. This needs a separate security/schema review and approval before implementation.

**Mapping caution:** the Customer audit's proposed target column names are explicitly candidates, not verified. The Admin app's existing Supabase service uses fields including `order_status`, `payment_status`, `total_amount`, and order-item `product_id`, `variant_id`, `unit_price`, `quantity`, and `subtotal`; reconcile the Customer model against the actual remote types, constraints, and relationship semantics before implementing any mapping.

### Customer-to-Admin order contract comparison

The Customer field names and enum values below are reported as verified by the Customer App source audit. Admin field names and effective authenticated table privileges are independently supported by the Admin source and linked-catalog inspection in this workspace. This comparison does **not** verify all remote column types, constraints, RLS behavior, or RPC semantics.

| Contract area | Customer App | Admin/shared Supabase evidence | Result |
| --- | --- | --- | --- |
| Order total | `totalPrice` | `orders.total_amount` | Name mismatch; mapping and amount precision/currency remain to verify. |
| Fulfillment status | `orderStatus`; `waitingPaymentVerification`, `preparing`, `readyForPickup`, `waitingPickup`, `completed`, `cancelled` | `orders.order_status`; Admin transition implementation and accepted values need confirmation against the full source/DB contract | Name mismatch; value/state-machine compatibility unknown. |
| Payment status | `paymentVerificationStatus`; `notSubmitted`, `waitingVerification`, `verified`, `rejected` | `orders.payment_status` | Name mismatch; accepted values and transition rules unknown. |
| Order items | Embedded Firestore `items` array | Relational `order_items` table | Structural mismatch; header/items need atomic persistence. |
| Item identifiers and snapshots | `productId`, `weight`, `price`, `quantity`, `subtotal` | `product_id`, `variant_id`, `unit_price`, `quantity`, `subtotal` | `quantity`/`subtotal` names align; identifier meaning, snapshot columns, types, and subtotal semantics remain unknown. |
| Guest write access | Firestore order write today | Remote check found no authenticated INSERT on `orders` or `order_items` | Direct authenticated table inserts are not currently available; secure guest-create API is a prerequisite. |
| Completion and stock | Customer audit reports no completion deduction | Admin/shared completion behavior must be confirmed as the single authoritative, atomic, idempotent operation before wiring Customer status changes | Unknown / implementation blocker. |

Still unresolved: actual `orders`/`order_items` types, nullability, defaults, constraints, keys and foreign keys; whether Customer `productId` is a product or variant ID; canonical status/payment vocabulary; customer/contact requirements; effective RLS and RPC behavior; product/storefront versus warehouse quantity semantics; and exact completion-time stock deduction behavior.

**Decision required before implementation:** agree on one field/value mapping and order state machine; define secure guest order creation and lookup with atomic item creation and retry idempotency; identify the Admin-owned payment/pickup/completion operation; and decide customer contact and private payment-proof ownership. No permissions or schema changes are approved by this comparison.

**Implication:** Product catalog connectivity is not a shared business-data cutover. The Customer App still needs a secure guest-order creation contract and durable order reads compatible with the Admin app. Do not infer that the app's reported Supabase URL or product query proves shared order access, schema compatibility, or correct RLS.

## Remaining Admin RTDB dependencies

| RTDB path or operation | Current Admin use | Supabase mapping / cutover note |
| --- | --- | --- |
| `/products` | Product CRUD and variant configuration; product views and dashboard/search reads | `products` + `product_variants`. The target tables exist, but current `authenticated` privileges are SELECT-only. |
| `/inventory` | Warehouse quantities, initialization, adjustments, production additions, and size-level scan comparison | `inventory` is present; authenticated SELECT is granted, but INSERT/UPDATE are not. Preserve this as the warehouse pool. |
| `/inventory_movements` | Stock history, replenishment, adjustments, production movement records, and dashboard activity | `inventory_movements` exists, but authenticated has no table privileges; its current policy is read-only. Writes need a deliberately scoped server-side/RLS design. |
| `/orders` and nested `items` | Legacy order streams, payment updates, completion, pickup reminders, production-related views, dashboard/search | `orders` + `order_items`; `orders` currently has authenticated SELECT/UPDATE, `order_items` SELECT only. Do not allow both RTDB and Supabase flows to mutate the same order during overlap. Keep payment validation, completion idempotency, and pickup validation in the approved Supabase RPC path. |
| `/production_batches`, nested `items` and `history` | Production CRUD/progress/completion/archive and production screens | `production_batches`, `production_batch_items`, and `production_history`. These tables exist, but authenticated has no table privileges. Nested RTDB structures need an explicit, loss-aware relational mapping. |
| `/suppliers` | Supplier stream and CRUD | `suppliers` exists, but authenticated has no table privileges despite a write policy. |
| `/customers` | Customer list/search and order/customer dashboards | `customers` exists, but authenticated has no table privileges. Confirm the Customer App's profile creation/update path before cutover. |
| `/admins` | Admin list/status stream and account name/status edits | `admins` exists; authenticated SELECT is granted. Account updates also need the supported Supabase Auth/admin workflow; do not use RTDB status as the authorization source. |
| `/admin_activity_logs` | Admin activity history and writes from operational actions | Table exists, but authenticated has no table privileges; the current policy is read-only. Preserve actor identity and audit semantics through a trusted server-side path. |
| `/notifications` | Admin notification list, read/archive changes, and notification creation | Table exists, but authenticated has no table privileges. The current policies describe read/update only; creation requires an explicit supported path. |
| `/conversations` and nested `/messages` | Support inbox, status/read updates, message send, automated pickup reminder messages | `conversations` + `messages` exist. Authenticated has no table privileges on either table. Model nested messages as separate rows while preserving order/customer links and timestamps. |
| `/feedback` | Feedback/review stream, read/archive/reply changes | Table exists, but authenticated has no table privileges. Current policy roles/operations must be paired with least-privilege SQL grants or a trusted RPC. |
| `/sales` | Read by the Owner Sales panel; no writer was found in `DatabaseService` | There is no `sales` table or view in the remote public catalog. Define the canonical sales calculation from orders and reconcile current metric differences before replacing this reader. |

Other direct RTDB business reads/writes exist outside `DatabaseService`:

- `DataInitializer` can seed Firebase `/products` and `/inventory` when the Firebase products node is empty, and checks Firebase `/admins`. Gate or remove those business-data behaviors as part of cutover; keep Firebase initialization needed for IoT.
- `GlobalSearchService` reads `/orders`, `/customers`, `/products`, `/production_batches`, and `/suppliers`.
- `main_dashboard.dart`, `production_page.dart`, `manage_accounts_page.dart`, `notifications_page.dart`, `messages_page.dart`, `owner_panel.dart`, and `dashboard_page.dart` contain direct RTDB reads or writes in addition to service calls. These must be migrated or intentionally retained, not missed by replacing only `DatabaseService`.
- `DatabaseService` obtains actor IDs from `FirebaseAuth.currentUser`, while the Admin sign-in path uses Supabase Auth. RTDB-created actor/creator fields may therefore be absent; ensure the replacement audit path uses the authenticated Supabase identity.

## Remote RLS and effective client privileges

Remote inspection confirmed RLS is enabled on the listed business tables and policies exist. A separate catalog privilege check showed those policies do **not** imply the authenticated role has SQL table privileges:

- Authenticated SELECT is currently available on `admins`, `inventory`, `order_items`, `orders`, `product_variants`, and `products`.
- Authenticated UPDATE is currently available only on `orders`.
- Authenticated has no table privileges on `admin_activity_logs`, `conversations`, `customers`, `feedback`, `inventory_movements`, `messages`, `notifications`, `production_batch_items`, `production_batches`, `production_history`, or `suppliers`.
- Authenticated INSERT is not available on `orders` or `order_items`. The Customer App order-creation path cannot be assumed to work through direct PostgREST writes.

**Cutover blocker:** Do not switch client calls based only on table existence or RLS policy names. Before each write flow moves, establish the minimum table/column grants and matching RLS predicates, or use a narrowly scoped server-side RPC. Do not solve this by granting broad table access or using the service-role key in either Flutter client.

The catalog has no `sales` table/view, `bottle_size_thresholds` table, or IoT transport tables. The missing sales object needs a defined view/query or a supported derived calculation. `bottle_size_thresholds` is scanner comparison configuration and can remain in Firebase with the ESP32-CAM workflow unless separately designed for relocation.

## Invariants for the coordinated two-app cutover

1. **One business source of truth:** Customer App and Admin Website/App must use the same Supabase project for business records. Do not dual-write or keep two active mutation paths for the same order, product, or stock quantity.
2. **Keep stock pools separate:** warehouse `inventory.quantity` and storefront `product_variants.product_qty` are distinct. Replenishment transfers between pools; production affects warehouse stock; eligible order completion deducts storefront stock exactly once.
3. **Keep payment and pickup gates:** payment verification and order completion remain distinct. Pickup must retain the approved role, ready-state, paid/confirmed, not-already-processed checks and atomic audit behavior.
4. **Preserve identity and relationships:** map existing IDs/external IDs, customer/order/product links, order items, production batch items/history, conversation messages, and audit actors without silently dropping records.
5. **Define sales consistently:** current Owner Dashboard totals use completed orders, while the Owner Sales panel includes orders marked Completed **or** Paid. Reconcile and approve one definition before replacing the RTDB `/sales` reader.
6. **Keep Firebase for ESP32-CAM IoT:** preserve `/scan_commands`, `/scan_results`, and `/iot_status/esp32_main`. Keep scan comparison verification-only; no camera discrepancy should directly alter either stock pool. The scanner's `/bottle_size_thresholds` configuration also currently remains in RTDB.
7. **Protect admin accounts:** preserve the active Co-Admin and Supabase Auth role/status checks. Firebase `/admins` must not remain an alternate authorization source after cutover.

## Coordinated cutover sequence

1. **Inspect the actual Customer App source** on its laptop or in a supplied repository/worktree. The shared snapshot is enough to identify risks, but not to verify the exact source, calls, or tests. Confirm Firestore order/message writes, guest checkout, auth state, notifier persistence, product mappings, and all remaining feature paths.
2. **Resolve guest-order authorization before implementation.** Decide a secure server-side order-create contract for anonymous customers, with idempotency and no client ability to read/update arbitrary orders. For Admin mutations, choose per-operation narrow grants/RLS or trusted RPCs; do not apply changes until separately approved.
3. **Create a source-to-target mapping and reconciliation plan** for both clients, especially order statuses/items/contact data, split stock pools, legacy IDs, nested production history/items, conversations/messages, audit events, and the differing sales definitions. Determine whether a final incremental export is needed from current RTDB/Firestore data.
4. **Implement both clients against the same approved Supabase contract.** Migrate every direct RTDB/Firestore business call, service call, search/report source, notifier-backed order flow, and initialization/seeding path. Keep only the ESP32-CAM IoT transport/configuration on Firebase.
5. **Validate in non-production or controlled fixtures first:** guest order creation and retry idempotency; durable cross-device order reads; dual-role access; payment verify/reject; one-time stock deduction; pickup rejection/acceptance; stock transfer/adjustment and movement history; production completion/history; notifications, conversations, messages, feedback, and account status. Reconcile resulting quantities and audit rows.
6. **Cut over both clients together** with an explicit freeze/rollback boundary. Verify both against `gvteqrtvpfujfrwrdohv`; only then disable Firebase business reads/writes. Do not retire Firebase or change ESP32 firmware/RTDB paths.
7. **Run a separate approved OTP readiness phase:** deploy the Edge Function, configure secret names in the server environment, choose durable worker hosting, add trusted-ingress rate limiting, then perform an explicitly approved end-to-end email/verification test. Do not report OTP as working before that test passes.

## Current decision and next action

**NO-GO for coordinated business-data cutover today.** The remote tables exist, but authenticated grants do not cover most Admin RTDB operations. The shared audit snapshot also reports Firestore-backed Customer orders/messages and no persistent cross-device order reads; the actual Customer App source and its behavior remain unverified here.

The next required input is access to the actual Customer App source for read-only verification. The first design decision to resolve is secure anonymous order creation and retrieval alongside least-privilege Admin writes. Firebase remains required for ESP32-CAM IoT throughout.
