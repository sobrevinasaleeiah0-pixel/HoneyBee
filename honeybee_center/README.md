# honeybee_center

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Automatic store-pickup reminder emails

When an eligible order has been ready for store pickup for at least 24 hours,
Supabase creates an in-app conversation reminder and queues an email. A
scheduled Supabase Edge Function sends the email through Resend. The ESP32-CAM
and Firebase are not part of this order-reminder flow.

### Supabase and Resend setup

Complete configuration in the Supabase and Resend dashboards before applying
the scheduling migration:

1. In Supabase **Database → Extensions**, ensure `pg_cron`, `pg_net`, and
   **Vault** are enabled. Do not enable or change production extensions without
   authorization.
2. In **Database → Vault**, create these two secrets with the exact names:
   - `project_url`: the project URL, such as `https://<project-ref>.supabase.co`.
   - `service_role_key`: the project's server-side service-role key. Keep it
     only in Vault and trusted server environments; never put it in Flutter,
     another client, or source control.
3. In Resend, verify the sending domain and the exact sender address you plan
   to use. In Supabase **Edge Functions → Secrets**, set:
   - `RESEND_API_KEY`: the Resend API key.
   - `RESEND_FROM_EMAIL`: the verified sender, for example
     `Honeybee Center <orders@your-verified-domain.example>`.
   Supabase provides `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to the
   Edge Function at runtime. Do not add either key to app configuration.
4. With the correct project linked and database authentication working, inspect
   migration status and preview the SQL before applying anything:

   ```powershell
   supabase migration list --linked
   supabase db push --dry-run
   ```

   Confirm that `20261016060000` and `20261016070000` are the exact pending
   migrations. Stop if the preview includes any unexpected migration.
5. After the preview is reviewed and production changes are approved, deploy
   the worker first, then apply the migrations so Cron cannot call a function
   that has not yet been deployed:

   ```powershell
   supabase functions deploy send-pickup-reminder-emails
   supabase db push
   ```

The existing in-app reminder runs every 15 minutes and becomes due 24 hours
after `ready_for_pickup_at`; its transaction inserts `pickup_followups`, which
queues one email in the outbox. The email worker runs every five minutes.
Retries use exponential backoff, capped at 60 minutes, and stop after eight
attempts. An order update cancels an unclaimed queued email when the order is
picked up or no longer `Ready for Pickup`; the worker also checks eligibility
when it claims jobs. A send already in progress cannot be recalled.

### Database authentication troubleshooting

The CLI's database password is separate from Supabase CLI/dashboard
authentication. A `password authentication failed` error means the database
credential available to the CLI is absent or does not match the current
database password; it does not indicate that the migrations were applied.
Use the existing password from an approved password manager or deployment
secret store. Do not reset or rotate it just to make this check pass.

To enter the existing password without putting it in command history or
printing it, run the following in PowerShell. It supplies the value only to
the current process environment and removes it when the checks finish:

```powershell
$securePassword = Read-Host "Enter the existing Supabase database password" -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $env:SUPABASE_DB_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
    supabase migration list --linked
    if ($LASTEXITCODE -ne 0) { throw "Could not read linked migration status" }
    supabase db push --dry-run
    if ($LASTEXITCODE -ne 0) { throw "Migration dry-run failed" }
}
finally {
    Remove-Item Env:SUPABASE_DB_PASSWORD -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    $securePassword.Dispose()
}
```

Do not run `supabase db push` until the dry-run has succeeded, its pending
migrations have been reviewed, and live application has been approved. Check
Edge Function logs and `pickup_reminder_email_outbox` for delivery outcomes.
