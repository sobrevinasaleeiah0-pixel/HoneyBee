-- Invoke the authenticated Supabase Edge Function on a schedule.
-- The function sends emails from the outbox populated by the pickup follow-up
-- transaction and the worker secrets are only read from Supabase Vault.
BEGIN;

DO $schedule$
DECLARE
  v_job_id bigint;
  v_command text;
  v_project_url text;
  v_service_role_key text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_cron'
  ) OR pg_catalog.to_regnamespace('cron') IS NULL THEN
    RAISE EXCEPTION 'Enable the Supabase Cron extension before this migration';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_net'
  ) OR pg_catalog.to_regnamespace('net') IS NULL THEN
    RAISE EXCEPTION 'Enable the Supabase pg_net extension before this migration';
  END IF;

  IF pg_catalog.to_regnamespace('vault') IS NULL THEN
    RAISE EXCEPTION 'Enable Supabase Vault and add project_url and service_role_key secrets';
  END IF;

  SELECT decrypted_secret INTO v_project_url
  FROM vault.decrypted_secrets
  WHERE name = 'project_url';

  SELECT decrypted_secret INTO v_service_role_key
  FROM vault.decrypted_secrets
  WHERE name = 'service_role_key';

  IF NULLIF(btrim(v_project_url), '') IS NULL
    OR NULLIF(btrim(v_service_role_key), '') IS NULL
  THEN
    RAISE EXCEPTION
      'Add project_url and service_role_key to Supabase Vault before this migration';
  END IF;

  v_command := $command$
    SELECT net.http_post(
      url := (
        SELECT rtrim(decrypted_secret, '/')
        FROM vault.decrypted_secrets
        WHERE name = 'project_url'
      ) || '/functions/v1/send-pickup-reminder-emails',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
        ),
        'apikey', (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = 'service_role_key'
        )
      ),
      body := '{}'::jsonb
    );
  $command$;

  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'honeybee-center-pickup-reminder-emails';

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;

  PERFORM cron.schedule(
    'honeybee-center-pickup-reminder-emails',
    '*/5 * * * *',
    v_command
  );
END;
$schedule$;

COMMIT;
