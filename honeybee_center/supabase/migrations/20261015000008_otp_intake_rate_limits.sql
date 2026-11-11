-- Server-side global and per-IP OTP endpoint token buckets.
-- IP keys are HMACed in the Edge Function and are never stored as raw IPs.
BEGIN;

CREATE TABLE public.otp_intake_rate_limits (
  subject_key text PRIMARY KEY
    CHECK (
      subject_key = 'global'
      OR subject_key ~ '^ip:[A-Za-z0-9_-]{43}$'
    ),
  tokens numeric(14, 6) NOT NULL CHECK (tokens >= 0),
  updated_at timestamptz NOT NULL,
  cleanup_after timestamptz
);

ALTER TABLE public.otp_intake_rate_limits OWNER TO postgres;
ALTER TABLE public.otp_intake_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.otp_intake_rate_limits
  FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX otp_intake_rate_limits_updated_idx
  ON public.otp_intake_rate_limits (updated_at)
  WHERE subject_key <> 'global';

CREATE OR REPLACE FUNCTION public.consume_otp_intake_quota(
  p_ip_hash text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_global public.otp_intake_rate_limits%ROWTYPE;
  v_ip public.otp_intake_rate_limits%ROWTYPE;
  v_global_tokens numeric(14, 6);
  v_ip_tokens numeric(14, 6);
  v_cleanup boolean;
  v_allowed boolean;
  v_ip_key text;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'consume_otp_intake_quota: service_role required';
  END IF;
  IF p_ip_hash IS NULL OR p_ip_hash !~ '^[A-Za-z0-9_-]{43}$' THEN
    RAISE EXCEPTION 'consume_otp_intake_quota: invalid IP hash';
  END IF;

  v_ip_key := 'ip:' || p_ip_hash;
  PERFORM pg_advisory_xact_lock(
    hashtextextended('otp-intake:global', 0)
  );
  PERFORM pg_advisory_xact_lock(
    hashtextextended('otp-intake:' || v_ip_key, 0)
  );

  INSERT INTO public.otp_intake_rate_limits (
    subject_key, tokens, updated_at, cleanup_after
  )
  VALUES ('global', 300, v_now, v_now + interval '1 hour')
  ON CONFLICT (subject_key) DO NOTHING;

  INSERT INTO public.otp_intake_rate_limits (
    subject_key, tokens, updated_at
  )
  VALUES (v_ip_key, 20, v_now)
  ON CONFLICT (subject_key) DO NOTHING;

  SELECT * INTO v_global
  FROM public.otp_intake_rate_limits
  WHERE subject_key = 'global'
  FOR UPDATE;

  SELECT * INTO v_ip
  FROM public.otp_intake_rate_limits
  WHERE subject_key = v_ip_key
  FOR UPDATE;

  v_global_tokens := least(
    300::numeric,
    v_global.tokens
      + greatest(0, extract(epoch FROM (v_now - v_global.updated_at))) * 5
  );
  v_ip_tokens := least(
    20::numeric,
    v_ip.tokens
      + greatest(0, extract(epoch FROM (v_now - v_ip.updated_at))) / 3
  );

  v_allowed := v_global_tokens >= 1 AND v_ip_tokens >= 1;
  IF v_allowed THEN
    v_global_tokens := v_global_tokens - 1;
    v_ip_tokens := v_ip_tokens - 1;
  END IF;

  UPDATE public.otp_intake_rate_limits
  SET tokens = v_global_tokens,
      updated_at = v_now,
      cleanup_after = CASE
        WHEN v_global.cleanup_after <= v_now
          THEN v_now + interval '1 hour'
        ELSE v_global.cleanup_after
      END
  WHERE subject_key = 'global';

  UPDATE public.otp_intake_rate_limits
  SET tokens = v_ip_tokens,
      updated_at = v_now
  WHERE subject_key = v_ip_key;

  v_cleanup := v_global.cleanup_after <= v_now;
  IF v_cleanup THEN
    DELETE FROM public.otp_intake_rate_limits
    WHERE subject_key <> 'global'
      AND updated_at < v_now - interval '1 day';
  END IF;

  RETURN v_allowed;
END;
$function$;

ALTER FUNCTION public.consume_otp_intake_quota(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.consume_otp_intake_quota(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_otp_intake_quota(text)
  TO service_role;

COMMIT;
