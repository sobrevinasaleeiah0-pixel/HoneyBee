-- Supabase-only global and per-email intake limits.
-- Supersedes the local-IP quota design from migration 20261015000008.
BEGIN;

ALTER TABLE public.otp_intake_rate_limits
  DROP CONSTRAINT IF EXISTS otp_intake_rate_limits_subject_key_check;

ALTER TABLE public.otp_intake_rate_limits
  ADD CONSTRAINT otp_intake_rate_limits_subject_key_check
  CHECK (
    subject_key = 'global'
    OR subject_key ~ '^email:[A-Za-z0-9_-]{43}$'
    OR subject_key ~ '^ip:[A-Za-z0-9_-]{43}$'
  );

CREATE OR REPLACE FUNCTION public.consume_otp_intake_bucket(
  p_subject_key text,
  p_capacity numeric,
  p_refill_per_second numeric
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_bucket public.otp_intake_rate_limits%ROWTYPE;
  v_tokens numeric(14, 6);
  v_allowed boolean;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'consume_otp_intake_bucket: service_role required';
  END IF;
  IF p_subject_key IS NULL
     OR (p_subject_key <> 'global'
         AND p_subject_key !~ '^email:[A-Za-z0-9_-]{43}$')
     OR p_capacity IS NULL OR p_capacity < 1 OR p_capacity > 300
     OR p_refill_per_second IS NULL OR p_refill_per_second <= 0
     OR p_refill_per_second > 5 THEN
    RAISE EXCEPTION 'consume_otp_intake_bucket: invalid bucket parameters';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended('otp-intake:' || p_subject_key, 0)
  );

  INSERT INTO public.otp_intake_rate_limits (
    subject_key, tokens, updated_at, cleanup_after
  )
  VALUES (
    p_subject_key,
    p_capacity,
    v_now,
    CASE
      WHEN p_subject_key = 'global' THEN v_now + interval '1 hour'
      ELSE NULL
    END
  )
  ON CONFLICT (subject_key) DO NOTHING;

  SELECT * INTO v_bucket
  FROM public.otp_intake_rate_limits
  WHERE subject_key = p_subject_key
  FOR UPDATE;

  v_tokens := least(
    p_capacity,
    v_bucket.tokens
      + greatest(0, extract(epoch FROM (v_now - v_bucket.updated_at)))
        * p_refill_per_second
  );
  v_allowed := v_tokens >= 1;

  UPDATE public.otp_intake_rate_limits
  SET tokens = CASE WHEN v_allowed THEN v_tokens - 1 ELSE v_tokens END,
      updated_at = v_now,
      cleanup_after = CASE
        WHEN p_subject_key = 'global'
             AND cleanup_after <= v_now
          THEN v_now + interval '1 hour'
        ELSE cleanup_after
      END
  WHERE subject_key = p_subject_key;

  IF p_subject_key = 'global'
     AND v_bucket.cleanup_after <= v_now THEN
    DELETE FROM public.otp_intake_rate_limits
    WHERE subject_key <> 'global'
      AND updated_at < v_now - interval '1 day';
  END IF;

  RETURN v_allowed;
END;
$function$;

ALTER FUNCTION public.consume_otp_intake_bucket(text, numeric, numeric)
  OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.consume_otp_global_quota()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'consume_otp_global_quota: service_role required';
  END IF;
  RETURN public.consume_otp_intake_bucket('global', 300, 5);
END;
$function$;

ALTER FUNCTION public.consume_otp_global_quota() OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.consume_otp_request_quota(
  p_email_hash text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'consume_otp_request_quota: service_role required';
  END IF;
  IF p_email_hash IS NULL OR p_email_hash !~ '^[A-Za-z0-9_-]{43}$' THEN
    RAISE EXCEPTION 'consume_otp_request_quota: invalid email hash';
  END IF;
  RETURN public.consume_otp_intake_bucket(
    'email:' || p_email_hash,
    5,
    5::numeric / 3600
  );
END;
$function$;

ALTER FUNCTION public.consume_otp_request_quota(text) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.consume_otp_intake_quota(text)
  FROM PUBLIC, anon, authenticated, service_role;
DROP FUNCTION public.consume_otp_intake_quota(text);

REVOKE ALL ON FUNCTION public.consume_otp_intake_bucket(text, numeric, numeric)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_otp_intake_bucket(text, numeric, numeric)
  TO service_role;

REVOKE ALL ON FUNCTION public.consume_otp_global_quota()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_otp_global_quota()
  TO service_role;

REVOKE ALL ON FUNCTION public.consume_otp_request_quota(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_otp_request_quota(text)
  TO service_role;

COMMIT;
