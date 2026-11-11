# OTP outbox worker

This Node.js worker polls the Supabase RPC outbox directly. It does not depend
on an unverified `pg_cron`, Vault, or `pgmq` installation. Run one or more
worker processes; PostgreSQL leases and `FOR UPDATE SKIP LOCKED` coordinate
concurrent workers.

From this directory:

```powershell
npm install
npm test
npm start
```

The worker requires these server-side environment variable names:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `OTP_SALT_SECRET` (independent high-entropy random secret; at least 32 bytes)
- `OTP_OUTBOX_ENCRYPTION_KEY` (base64url encoding of 32 random bytes)
- `SMTP_USER`
- `SMTP_PASS`

Do not place values in source, `.env` files committed to the repository, or
Flutter configuration. In deployment, inject them through the worker host's
secret manager. The current Edge Function only requires the first four names;
SMTP credentials are used only by this worker.

SMTP defaults to Gmail (`SMTP_HOST=smtp.gmail.com`, `SMTP_PORT=465`,
`SMTP_SECURE=true`). To use another provider, set the non-secret worker
configuration `SMTP_HOST`, `SMTP_PORT`, and `SMTP_SECURE` (`true` or `false`).
`SMTP_FROM` is optional and defaults to `SMTP_USER`; configure the provider's
verified sender address there when it differs. For Gmail, use an app password
with SMTP enabled, not the account's regular password. Store `SMTP_USER` and
`SMTP_PASS` in the worker host's secret manager.

The public Admin client calls the Supabase OTP Edge Function directly. The
database-backed global token bucket allows a 300-request burst and restores
five tokens per second. OTP requests are additionally limited to a burst of
five per normalized email identity, refilling at five per hour. The email
identity key is salted and hashed by the Edge Function; raw emails are not
stored in the rate-limit table. These controls do not claim per-IP protection:
this deployment intentionally keeps the business backend Supabase-only. The
quota schema is introduced by `20261015000008_otp_intake_rate_limits.sql` and
the Supabase-only global/email quota functions by
`20261016030000_otp_supabase_intake_limits.sql`.

The intake Edge Function enqueues every valid-format address without looking
up an admin and returns after the database commit. The worker asynchronously
checks eligibility, issues one OTP through a transactional RPC, and sends the
encrypted outbox payload. The outbox keeps one stable OTP across SMTP retries.
SMTP acceptance followed by a worker crash can produce a duplicate email, but
not a second valid code. OTP activation occurs only after a successful SMTP
acknowledgement. PostgreSQL enforces the 30-second resend cooldown, five
minutes of OTP validity, five failed verification attempts, and a maximum of
five OTP generations and five SMTP attempt reservations per email hash in
every rolling 60-minute window. Database time determines generation expiry
and cooldown. Every SMTP attempt is reserved before the worker calls SMTP;
crashes before actual delivery still consume an attempt, which is conservative
and prevents concurrent workers or retries exceeding the cap. The worker lease
is 60 seconds; an expired lease can be reclaimed, but an active lease is never
cleared by the fifth-attempt cleanup.

Worker unit tests use injected stores/transports and do not connect to Supabase
or send email. Database concurrency and RPC behavior still require execution
of the SQL migration tests against an isolated local PostgreSQL/Supabase
instance.

OTP issuance is additionally limited to five generations per email hash per
rolling hour, with a 30-second resend cooldown and five verification attempts.

No key-versioning/rotation workflow is implemented. Keep the outbox encryption
key stable while pending jobs exist; rotating it early makes those encrypted
emails unreadable. Rotate the OTP salt only after pending OTP/reset flows are
drained, because it also keys email identity and OTP hashes.
