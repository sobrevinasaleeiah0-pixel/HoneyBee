-- Stage 5: durable OTP request intake and encrypted email outbox.
-- Local draft only. Do not apply remotely without separate approval.

REVOKE ALL ON public.otp_sessions, public.password_reset_sessions
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.otp_sessions, public.password_reset_sessions TO service_role;

ALTER TABLE public.otp_sessions
  ADD COLUMN IF NOT EXISTS delivery_state text NOT NULL DEFAULT 'active'
    CHECK (delivery_state IN ('pending_delivery', 'active', 'invalid')),
  ADD COLUMN IF NOT EXISTS generation_id uuid;

CREATE TABLE public.otp_request_jobs (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  email_hash           text        NOT NULL,
  email_ciphertext     text        NOT NULL,
  status               text        NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'complete')),
  worker_token         uuid,
  lease_until          timestamptz,
  available_at         timestamptz NOT NULL DEFAULT now(),
  attempts             integer     NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  requested_at         timestamptz NOT NULL DEFAULT now(),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.otp_email_outbox (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  request_job_id   uuid        NOT NULL UNIQUE REFERENCES public.otp_request_jobs(id)
                                ON DELETE CASCADE,
  generation_id    uuid        NOT NULL UNIQUE,
  email_hash       text        NOT NULL,
  user_id          uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email_ciphertext text        NOT NULL,
  otp_ciphertext   text        NOT NULL,
  expires_at       timestamptz NOT NULL,
  status           text        NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'stale')),
  attempts         integer     NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  available_at    timestamptz NOT NULL DEFAULT now(),
  worker_token     uuid,
  lease_until      timestamptz,
  sent_at          timestamptz,
  last_error       text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.otp_email_rate_events (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email_hash     text        NOT NULL,
  outbox_job_id  uuid        NOT NULL REFERENCES public.otp_email_outbox(id)
                             ON DELETE CASCADE,
  event_type     text        NOT NULL
    CHECK (event_type IN ('otp_issued', 'smtp_attempt')),
  worker_token   uuid        NOT NULL,
  occurred_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (outbox_job_id, event_type, worker_token)
);

CREATE INDEX otp_request_jobs_claim_idx
  ON public.otp_request_jobs (available_at, requested_at)
  WHERE status = 'pending';
CREATE INDEX otp_request_jobs_email_created_idx
  ON public.otp_request_jobs (email_hash, requested_at);
CREATE INDEX otp_email_outbox_claim_idx
  ON public.otp_email_outbox (available_at, created_at)
  WHERE status IN ('pending', 'sending');
CREATE UNIQUE INDEX otp_email_outbox_one_live_per_email_idx
  ON public.otp_email_outbox (email_hash)
  WHERE status IN ('pending', 'sending');
CREATE INDEX otp_email_rate_events_rolling_idx
  ON public.otp_email_rate_events (email_hash, event_type, occurred_at DESC);

ALTER TABLE public.otp_request_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_email_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.otp_email_rate_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.otp_request_jobs, public.otp_email_outbox,
  public.otp_email_rate_events
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.otp_request_jobs, public.otp_email_outbox,
     public.otp_email_rate_events TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.otp_email_rate_events_id_seq TO service_role;

CREATE OR REPLACE FUNCTION public.enqueue_otp_request(
  p_email_hash       text,
  p_email_ciphertext text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'enqueue_otp_request: service_role required';
  END IF;
  IF p_email_hash IS NULL OR p_email_hash = ''
     OR p_email_ciphertext IS NULL OR p_email_ciphertext = ''
     OR length(p_email_ciphertext) > 2048 THEN
    RAISE EXCEPTION 'enqueue_otp_request: invalid request';
  END IF;

  -- Keep the request path to one independent durable insert. It does not
  -- inspect or lock account/session state, avoiding eligibility-dependent
  -- reads and per-email lock waits.
  INSERT INTO public.otp_request_jobs (email_hash, email_ciphertext)
  VALUES (p_email_hash, p_email_ciphertext);
  RETURN 'QUEUED';
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_otp_request_jobs(
  p_worker_token uuid,
  p_batch_size integer DEFAULT 10
)
RETURNS SETOF public.otp_request_jobs
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'claim_otp_request_jobs: service_role required';
  END IF;
  IF p_worker_token IS NULL OR p_batch_size < 1 OR p_batch_size > 50 THEN
    RAISE EXCEPTION 'claim_otp_request_jobs: invalid claim parameters';
  END IF;

  DELETE FROM public.otp_request_jobs
   WHERE status = 'complete'
     AND updated_at < clock_timestamp() - interval '1 day';
  DELETE FROM public.password_reset_sessions
   WHERE expires_at < clock_timestamp() - interval '1 day'
      OR claimed_at < clock_timestamp() - interval '1 day';

  UPDATE public.otp_request_jobs
     SET status = 'complete', email_ciphertext = '', worker_token = NULL,
         lease_until = NULL, updated_at = clock_timestamp()
   WHERE status = 'processing' AND lease_until < clock_timestamp()
     AND attempts >= 5;

  RETURN QUERY
  WITH candidates AS (
    SELECT id
      FROM public.otp_request_jobs
     WHERE (status = 'pending' AND available_at <= clock_timestamp())
        OR (status = 'processing' AND lease_until < clock_timestamp()
            AND attempts < 5)
     ORDER BY requested_at
     FOR UPDATE SKIP LOCKED
     LIMIT p_batch_size
  )
  UPDATE public.otp_request_jobs AS job
     SET status = 'processing',
         worker_token = p_worker_token,
         lease_until = clock_timestamp() + interval '60 seconds',
         attempts = attempts + 1,
         updated_at = clock_timestamp()
    FROM candidates
   WHERE job.id = candidates.id
  RETURNING job.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.retry_otp_request_job(
  p_job_id uuid,
  p_worker_token uuid,
  p_delay_seconds integer
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_job public.otp_request_jobs%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'retry_otp_request_job: service_role required';
  END IF;
  IF p_delay_seconds < 1 OR p_delay_seconds > 60 THEN
    RAISE EXCEPTION 'retry_otp_request_job: invalid retry delay';
  END IF;
  SELECT * INTO v_job FROM public.otp_request_jobs
   WHERE id = p_job_id AND status = 'processing'
     AND worker_token = p_worker_token FOR UPDATE;
  IF NOT FOUND THEN RETURN 'STALE'; END IF;
  IF v_job.attempts >= 5 THEN
    UPDATE public.otp_request_jobs SET status = 'complete',
      email_ciphertext = '', worker_token = NULL, lease_until = NULL,
      updated_at = clock_timestamp() WHERE id = p_job_id;
    RETURN 'FAILED';
  END IF;
  UPDATE public.otp_request_jobs SET status = 'pending',
    available_at = clock_timestamp() + make_interval(secs => p_delay_seconds),
    worker_token = NULL, lease_until = NULL, updated_at = clock_timestamp()
   WHERE id = p_job_id;
  RETURN 'RETRY';
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_otp_request_job(
  p_job_id       uuid,
  p_worker_token uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'finish_otp_request_job: service_role required';
  END IF;
  UPDATE public.otp_request_jobs
     SET status = 'complete',
         worker_token = NULL,
         lease_until = NULL,
         email_ciphertext = '',
         updated_at = clock_timestamp()
   WHERE id = p_job_id
     AND status = 'processing'
     AND worker_token = p_worker_token;
  RETURN FOUND;
END;
$$;

DROP FUNCTION IF EXISTS public.issue_otp_email_job(
  uuid, uuid, uuid, text, text, text, timestamptz, timestamptz
);

CREATE OR REPLACE FUNCTION public.issue_otp_email_job(
  p_job_id          uuid,
  p_worker_token    uuid,
  p_user_id         uuid,
  p_email           text,
  p_otp_hash        text,
  p_otp_ciphertext  text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job     public.otp_request_jobs%ROWTYPE;
  v_session public.otp_sessions%ROWTYPE;
  v_now     timestamptz := clock_timestamp();
  v_gen     uuid := gen_random_uuid();
  v_has_session boolean;
  v_recent_issues integer;
  v_expires_at timestamptz;
  v_resend_at timestamptz;
  v_outbox_id uuid;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'issue_otp_email_job: service_role required';
  END IF;
  IF p_job_id IS NULL OR p_worker_token IS NULL OR p_user_id IS NULL
     OR p_email IS NULL OR p_email = ''
     OR p_otp_hash IS NULL OR p_otp_hash = ''
     OR p_otp_ciphertext IS NULL OR p_otp_ciphertext = '' THEN
    RAISE EXCEPTION 'issue_otp_email_job: invalid issue parameters';
  END IF;

  SELECT * INTO v_job
    FROM public.otp_request_jobs
   WHERE id = p_job_id
     AND status = 'processing'
     AND worker_token = p_worker_token
     AND lease_until > v_now
   FOR UPDATE;
  IF NOT FOUND THEN RETURN 'STALE'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_job.email_hash, 0));
  v_now := clock_timestamp();

  IF NOT EXISTS (
    SELECT 1 FROM public.admins
     WHERE id = p_user_id AND status = 'active'
       AND role IN ('main_admin', 'co_admin')
       AND lower(email) = lower(trim(p_email))
  ) THEN
    UPDATE public.otp_request_jobs
       SET status = 'complete', email_ciphertext = '',
           worker_token = NULL, lease_until = NULL, updated_at = v_now
     WHERE id = p_job_id;
    RETURN 'INELIGIBLE';
  END IF;

  -- Read cooldown state without taking its row lock yet. The advisory lock
  -- serializes issuers; this preserves cooldown precedence without reversing
  -- the outbox-before-session lock order shared with email claims.
  SELECT * INTO v_session FROM public.otp_sessions
   WHERE email_hash = v_job.email_hash;
  v_has_session := FOUND;
  IF v_has_session AND clock_timestamp() < v_session.resend_at THEN
    UPDATE public.otp_request_jobs
       SET status = 'complete', email_ciphertext = '',
           worker_token = NULL, lease_until = NULL,
           updated_at = clock_timestamp()
     WHERE id = p_job_id;
    RETURN 'COOLDOWN';
  END IF;

  -- Lock live-generation jobs before locking or changing the session row. The
  -- email advisory lock serializes issuers; the outbox-first row lock order
  -- matches claim_otp_email_jobs and its cleanup path.
  PERFORM 1
    FROM public.otp_email_outbox
   WHERE email_hash = v_job.email_hash
     AND status IN ('pending', 'sending')
   ORDER BY id
   FOR UPDATE;

  IF EXISTS (
    SELECT 1 FROM public.otp_email_outbox
     WHERE email_hash = v_job.email_hash
       AND status = 'sending'
       AND lease_until > clock_timestamp()
  ) THEN
    UPDATE public.otp_request_jobs
       SET status = 'complete', email_ciphertext = '',
           worker_token = NULL, lease_until = NULL, updated_at = clock_timestamp()
     WHERE id = p_job_id;
    RETURN 'DELIVERY_PENDING';
  END IF;

  SELECT * INTO v_session FROM public.otp_sessions
   WHERE email_hash = v_job.email_hash FOR UPDATE;
  v_has_session := FOUND;
  v_now := clock_timestamp();
  IF v_has_session AND v_now < v_session.resend_at THEN
    UPDATE public.otp_request_jobs
       SET status = 'complete', email_ciphertext = '',
           worker_token = NULL, lease_until = NULL, updated_at = v_now
     WHERE id = p_job_id;
    RETURN 'COOLDOWN';
  END IF;

  SELECT count(*)::integer INTO v_recent_issues
    FROM public.otp_email_rate_events
   WHERE email_hash = v_job.email_hash
     AND event_type = 'otp_issued'
     AND occurred_at > v_now - interval '1 hour';
  IF v_recent_issues >= 5 THEN
    UPDATE public.otp_request_jobs
       SET status = 'complete', email_ciphertext = '',
           worker_token = NULL, lease_until = NULL, updated_at = v_now
     WHERE id = p_job_id;
    RETURN 'RATE_LIMITED';
  END IF;
  v_expires_at := v_now + interval '5 minutes';
  v_resend_at := v_now + interval '30 seconds';

  UPDATE public.otp_email_outbox
     SET status = 'stale', email_ciphertext = '', otp_ciphertext = '', worker_token = NULL,
         lease_until = NULL, updated_at = v_now
   WHERE email_hash = v_job.email_hash
     AND (
       status = 'pending'
       OR (status = 'sending' AND lease_until <= v_now)
     );

  INSERT INTO public.otp_sessions
    (email_hash, user_id, otp_hash, expires_at, attempts, send_count,
     send_window_start, resend_at, created_at, delivery_state, generation_id)
  VALUES
    (v_job.email_hash, p_user_id, p_otp_hash, v_expires_at, 0,
     v_recent_issues + 1, v_now, v_resend_at, v_now,
     'pending_delivery', v_gen)
  ON CONFLICT (email_hash) DO UPDATE SET
    user_id = EXCLUDED.user_id,
    otp_hash = EXCLUDED.otp_hash,
    expires_at = EXCLUDED.expires_at,
    attempts = 0,
    send_count = v_recent_issues + 1,
    send_window_start = v_now,
    resend_at = EXCLUDED.resend_at,
    created_at = v_now,
    delivery_state = 'pending_delivery',
    generation_id = v_gen;

  INSERT INTO public.otp_email_outbox
    (request_job_id, generation_id, email_hash, user_id, email_ciphertext,
     otp_ciphertext, expires_at)
  VALUES
    (p_job_id, v_gen, v_job.email_hash, p_user_id, v_job.email_ciphertext,
     p_otp_ciphertext, v_expires_at)
  RETURNING id INTO v_outbox_id;

  INSERT INTO public.otp_email_rate_events
    (email_hash, outbox_job_id, event_type, worker_token, occurred_at)
  VALUES
    (v_job.email_hash, v_outbox_id, 'otp_issued', p_worker_token, v_now);

  UPDATE public.otp_request_jobs
     SET status = 'complete', email_ciphertext = '',
         worker_token = NULL, lease_until = NULL, updated_at = v_now
   WHERE id = p_job_id;
  RETURN 'ISSUED';
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_otp_email_jobs(
  p_worker_token uuid,
  p_batch_size integer DEFAULT 10
)
RETURNS SETOF public.otp_email_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_candidate record;
  v_job public.otp_email_outbox%ROWTYPE;
  v_session public.otp_sessions%ROWTYPE;
  v_now timestamptz;
  v_recent_attempts integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'claim_otp_email_jobs: service_role required';
  END IF;
  IF p_worker_token IS NULL OR p_batch_size < 1 OR p_batch_size > 50 THEN
    RAISE EXCEPTION 'claim_otp_email_jobs: invalid claim parameters';
  END IF;

  v_now := clock_timestamp();
  DELETE FROM public.otp_email_rate_events
   WHERE occurred_at <= v_now - interval '1 hour';

  UPDATE public.otp_email_outbox AS job
     SET status = 'failed', otp_ciphertext = '', email_ciphertext = '',
         worker_token = NULL, lease_until = NULL,
         last_error = CASE
           WHEN job.expires_at <= v_now THEN 'expired'
           ELSE 'attempt_limit'
         END,
         updated_at = v_now
   WHERE job.status IN ('pending', 'sending')
     AND ((job.expires_at <= v_now
           AND (job.status = 'pending' OR job.lease_until <= v_now))
          OR (job.attempts >= 5
              AND (job.status = 'pending' OR job.lease_until <= v_now)));

  UPDATE public.otp_email_outbox AS job
     SET status = 'failed', otp_ciphertext = '', email_ciphertext = '',
         worker_token = NULL, lease_until = NULL,
         last_error = 'hourly_send_limit', updated_at = v_now
    FROM public.otp_sessions AS otp
   WHERE job.email_hash = otp.email_hash
     AND job.generation_id = otp.generation_id
     AND otp.delivery_state = 'pending_delivery'
     AND (job.status = 'pending'
          OR (job.status = 'sending' AND job.lease_until <= v_now))
     AND (
       SELECT count(*)
         FROM public.otp_email_rate_events AS event
        WHERE event.email_hash = job.email_hash
          AND event.event_type = 'smtp_attempt'
          AND event.occurred_at > v_now - interval '1 hour'
     ) >= 5;

  UPDATE public.otp_sessions AS otp
     SET delivery_state = 'invalid', otp_hash = ''
   WHERE otp.delivery_state = 'pending_delivery'
     AND NOT EXISTS (
       SELECT 1 FROM public.otp_email_outbox AS job
        WHERE job.email_hash = otp.email_hash
          AND job.generation_id = otp.generation_id
           AND (
             (job.status = 'sending' AND job.lease_until > clock_timestamp())
             OR (
               job.expires_at > clock_timestamp()
               AND (
                 (
                   job.status = 'pending'
                   AND job.attempts < 5
                   AND (
                     SELECT count(*)
                       FROM public.otp_email_rate_events AS event
                      WHERE event.email_hash = job.email_hash
                        AND event.event_type = 'smtp_attempt'
                        AND event.occurred_at > clock_timestamp() - interval '1 hour'
                   ) < 5
                 )
                 OR (
                   job.status = 'sending'
                   AND job.lease_until <= clock_timestamp()
                   AND job.attempts < 5
                   AND (
                     SELECT count(*)
                       FROM public.otp_email_rate_events AS event
                      WHERE event.email_hash = job.email_hash
                        AND event.event_type = 'smtp_attempt'
                        AND event.occurred_at > clock_timestamp() - interval '1 hour'
                   ) < 5
                 )
               )
             )
           )
     );

  FOR v_candidate IN
    SELECT job.id, job.email_hash, job.generation_id
      FROM public.otp_sessions AS otp
      JOIN public.otp_email_outbox AS job
        ON job.email_hash = otp.email_hash
       AND job.generation_id = otp.generation_id
     WHERE otp.delivery_state = 'pending_delivery'
       AND job.expires_at > v_now
       AND job.attempts < 5
       AND (
         (job.status = 'pending' AND job.available_at <= v_now)
         OR (job.status = 'sending' AND job.lease_until <= v_now)
       )
       AND (
         SELECT count(*)
           FROM public.otp_email_rate_events AS event
          WHERE event.email_hash = otp.email_hash
            AND event.event_type = 'smtp_attempt'
            AND event.occurred_at > v_now - interval '1 hour'
       ) < 5
     ORDER BY job.available_at, job.created_at
     LIMIT p_batch_size
  LOOP
    v_now := clock_timestamp();
    SELECT * INTO v_job
      FROM public.otp_email_outbox AS job
     WHERE job.id = v_candidate.id
       AND job.email_hash = v_candidate.email_hash
       AND job.generation_id = v_candidate.generation_id
       AND job.expires_at > v_now
       AND job.attempts < 5
       AND (
         (job.status = 'pending' AND job.available_at <= v_now)
         OR (job.status = 'sending' AND job.lease_until <= v_now)
       )
     FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    SELECT * INTO v_session
      FROM public.otp_sessions
     WHERE email_hash = v_job.email_hash
       AND generation_id = v_job.generation_id
       AND delivery_state = 'pending_delivery'
     FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_now := clock_timestamp();
    IF v_job.expires_at <= v_now OR v_job.attempts >= 5
       OR NOT (
         (v_job.status = 'pending' AND v_job.available_at <= v_now)
         OR (v_job.status = 'sending' AND v_job.lease_until <= v_now)
       ) THEN
      CONTINUE;
    END IF;

    SELECT count(*)::integer INTO v_recent_attempts
      FROM public.otp_email_rate_events AS event
     WHERE event.email_hash = v_job.email_hash
       AND event.event_type = 'smtp_attempt'
       AND event.occurred_at > v_now - interval '1 hour';
    IF v_recent_attempts >= 5 THEN
      UPDATE public.otp_email_outbox
         SET status = 'failed', email_ciphertext = '', otp_ciphertext = '',
             worker_token = NULL, lease_until = NULL,
             last_error = 'hourly_send_limit', updated_at = v_now
       WHERE id = v_job.id;
      UPDATE public.otp_sessions
         SET delivery_state = 'invalid', otp_hash = ''
       WHERE email_hash = v_job.email_hash
         AND generation_id = v_job.generation_id
         AND delivery_state = 'pending_delivery';
      CONTINUE;
    END IF;

    INSERT INTO public.otp_email_rate_events
      (email_hash, outbox_job_id, event_type, worker_token, occurred_at)
    VALUES
      (v_job.email_hash, v_job.id, 'smtp_attempt', p_worker_token, v_now);

    UPDATE public.otp_email_outbox AS job
       SET status = 'sending',
           worker_token = p_worker_token,
           lease_until = v_now + interval '60 seconds',
           attempts = attempts + 1,
           updated_at = v_now
     WHERE job.id = v_job.id
    RETURNING job.* INTO v_job;
    RETURN NEXT v_job;
  END LOOP;
  RETURN;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_otp_email_job(
  p_job_id uuid,
  p_worker_token uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.otp_email_outbox%ROWTYPE;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'complete_otp_email_job: service_role required';
  END IF;
  SELECT * INTO v_job FROM public.otp_email_outbox
   WHERE id = p_job_id AND status = 'sending'
     AND worker_token = p_worker_token AND lease_until > clock_timestamp()
   FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;

  UPDATE public.otp_sessions
     SET delivery_state = 'active'
   WHERE email_hash = v_job.email_hash
     AND generation_id = v_job.generation_id
     AND delivery_state = 'pending_delivery'
     AND expires_at > clock_timestamp();
  IF NOT FOUND THEN
    UPDATE public.otp_email_outbox SET status = 'stale',
      email_ciphertext = '', otp_ciphertext = '', worker_token = NULL, lease_until = NULL,
      updated_at = clock_timestamp() WHERE id = p_job_id;
    RETURN false;
  END IF;
  UPDATE public.otp_email_outbox
     SET status = 'sent', sent_at = clock_timestamp(), otp_ciphertext = '',
         email_ciphertext = '', worker_token = NULL, lease_until = NULL,
         updated_at = clock_timestamp()
   WHERE id = p_job_id;
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.retry_otp_email_job(
  p_job_id uuid,
  p_worker_token uuid,
  p_delay_seconds integer,
  p_error text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job public.otp_email_outbox%ROWTYPE;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'retry_otp_email_job: service_role required';
  END IF;
  IF p_delay_seconds < 1 OR p_delay_seconds > 60 THEN
    RAISE EXCEPTION 'retry_otp_email_job: invalid retry delay';
  END IF;
  SELECT * INTO v_job FROM public.otp_email_outbox
   WHERE id = p_job_id AND status = 'sending' AND worker_token = p_worker_token
     AND lease_until > v_now
   FOR UPDATE;
  IF NOT FOUND THEN RETURN 'STALE'; END IF;

  IF v_job.expires_at <= v_now OR v_job.attempts >= 5 THEN
    UPDATE public.otp_email_outbox SET status = 'failed', email_ciphertext = '', otp_ciphertext = '',
      worker_token = NULL, lease_until = NULL,
      last_error = left(COALESCE(p_error, ''), 160), updated_at = v_now
     WHERE id = p_job_id;
    UPDATE public.otp_sessions SET delivery_state = 'invalid', otp_hash = ''
     WHERE email_hash = v_job.email_hash
       AND generation_id = v_job.generation_id
       AND delivery_state = 'pending_delivery';
    RETURN 'FAILED';
  END IF;

  UPDATE public.otp_email_outbox SET status = 'pending',
    available_at = LEAST(v_now + make_interval(secs => p_delay_seconds), expires_at),
    worker_token = NULL, lease_until = NULL,
    last_error = left(COALESCE(p_error, ''), 160), updated_at = v_now
   WHERE id = p_job_id;
  RETURN 'RETRY';
END;
$$;

CREATE OR REPLACE FUNCTION public.verify_admin_otp(
  p_email_hash text,
  p_email text,
  p_otp_hash text,
  p_token_hash text,
  p_reset_expires_at timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session public.otp_sessions%ROWTYPE;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'verify_admin_otp: service_role required';
  END IF;
  SELECT * INTO v_session FROM public.otp_sessions
   WHERE email_hash = p_email_hash FOR UPDATE;
  v_now := clock_timestamp();
  IF NOT FOUND OR v_session.delivery_state <> 'active'
     OR v_session.expires_at <= v_now OR v_session.attempts >= 5 THEN
    RETURN NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.admins
     WHERE id = v_session.user_id AND status = 'active'
       AND role IN ('main_admin', 'co_admin')
       AND lower(email) = lower(trim(p_email))
  ) THEN
    UPDATE public.otp_sessions SET delivery_state = 'invalid', otp_hash = ''
     WHERE email_hash = p_email_hash;
    RETURN NULL;
  END IF;
  IF v_session.otp_hash IS DISTINCT FROM p_otp_hash THEN
    UPDATE public.otp_sessions SET attempts = attempts + 1
     WHERE email_hash = p_email_hash;
    RETURN NULL;
  END IF;
  IF p_reset_expires_at <= v_now OR p_reset_expires_at > v_now + interval '15 minutes' THEN
    RAISE EXCEPTION 'verify_admin_otp: invalid reset expiry';
  END IF;

  INSERT INTO public.password_reset_sessions (token_hash, user_id, email, expires_at)
  VALUES (p_token_hash, v_session.user_id, lower(trim(p_email)), p_reset_expires_at);
  UPDATE public.otp_sessions SET delivery_state = 'invalid', otp_hash = ''
   WHERE email_hash = p_email_hash;
  RETURN v_session.user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_password_reset_session(p_token_hash text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_user_id uuid;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'claim_password_reset_session: service_role required';
  END IF;
  UPDATE public.password_reset_sessions AS reset_session
     SET claimed_at = clock_timestamp()
   WHERE reset_session.token_hash = p_token_hash
     AND reset_session.claimed_at IS NULL
     AND reset_session.expires_at > clock_timestamp()
     AND EXISTS (
       SELECT 1 FROM public.admins
        WHERE admins.id = reset_session.user_id
          AND admins.status = 'active'
          AND admins.role IN ('main_admin', 'co_admin')
     )
  RETURNING reset_session.user_id INTO v_user_id;
  RETURN v_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.invalidate_otp_session(p_email_hash text, p_otp_hash text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'invalidate_otp_session: service_role required';
  END IF;
  UPDATE public.otp_sessions SET delivery_state = 'invalid', otp_hash = ''
   WHERE email_hash = p_email_hash AND otp_hash = p_otp_hash;
  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.request_otp_session(text, uuid, text, timestamptz, timestamptz, timestamptz)
  FROM PUBLIC, anon, authenticated;
DROP FUNCTION IF EXISTS public.request_otp_session(text, uuid, text, timestamptz, timestamptz, timestamptz);

DO $$
DECLARE f record;
BEGIN
  FOR f IN SELECT p.oid::regprocedure AS signature
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname IN (
                'enqueue_otp_request', 'claim_otp_request_jobs',
                'retry_otp_request_job', 'finish_otp_request_job', 'issue_otp_email_job',
                'claim_otp_email_jobs', 'complete_otp_email_job',
                'retry_otp_email_job', 'verify_admin_otp',
                'claim_password_reset_session', 'invalidate_otp_session'
              )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f.signature);
  END LOOP;
END;
$$;
