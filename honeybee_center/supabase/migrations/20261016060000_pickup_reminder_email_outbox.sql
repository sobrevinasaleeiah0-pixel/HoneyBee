-- Queue email delivery for the scheduled store-pickup conversation follow-up.
-- A trusted Supabase Edge Function claims and sends these emails through Resend.
BEGIN;

CREATE TABLE public.pickup_reminder_email_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL UNIQUE
    REFERENCES public.orders(id) ON DELETE RESTRICT,
  recipient_email text NOT NULL,
  customer_name text NOT NULL,
  order_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  claim_token uuid,
  locked_until timestamptz,
  sent_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  last_error text,
  CONSTRAINT pickup_reminder_email_outbox_single_terminal_state
    CHECK (num_nonnulls(sent_at, failed_at, cancelled_at) <= 1)
);

ALTER TABLE public.pickup_reminder_email_outbox OWNER TO postgres;
ALTER TABLE public.pickup_reminder_email_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pickup_reminder_email_outbox
  FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX idx_pickup_reminder_email_outbox_pending
  ON public.pickup_reminder_email_outbox (next_attempt_at, created_at)
  WHERE sent_at IS NULL AND failed_at IS NULL AND cancelled_at IS NULL;

CREATE OR REPLACE FUNCTION public.cancel_ineligible_pickup_reminder_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NEW.order_status <> 'Ready for Pickup' OR NEW.picked_up_at IS NOT NULL THEN
    UPDATE public.pickup_reminder_email_outbox AS outbox
    SET cancelled_at = now(),
        last_error = 'Order is no longer eligible for a pickup reminder'
    WHERE outbox.order_id = NEW.id
      AND outbox.sent_at IS NULL
      AND outbox.failed_at IS NULL
      AND outbox.cancelled_at IS NULL
      AND outbox.locked_until IS NULL;
  END IF;

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.cancel_ineligible_pickup_reminder_email() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.cancel_ineligible_pickup_reminder_email()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER orders_cancel_ineligible_pickup_reminder_email
  AFTER UPDATE OF order_status, picked_up_at ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.cancel_ineligible_pickup_reminder_email();

CREATE OR REPLACE FUNCTION public.enqueue_pickup_reminder_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  INSERT INTO public.pickup_reminder_email_outbox (
    order_id, recipient_email, customer_name, order_reference
  )
  SELECT order_row.id, customer.email, customer.name, order_row.order_reference
  FROM public.orders AS order_row
  JOIN public.customers AS customer ON customer.id = order_row.customer_id
  WHERE order_row.id = NEW.order_id
    AND customer.status = 'active'
    AND customer.auth_uid IS NOT NULL
    AND NULLIF(btrim(customer.email), '') IS NOT NULL
  ON CONFLICT (order_id) DO NOTHING;

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.enqueue_pickup_reminder_email() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enqueue_pickup_reminder_email()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS pickup_followups_enqueue_email
  ON public.pickup_followups;
CREATE TRIGGER pickup_followups_enqueue_email
  AFTER INSERT ON public.pickup_followups
  FOR EACH ROW
  EXECUTE FUNCTION public.enqueue_pickup_reminder_email();

CREATE OR REPLACE FUNCTION public.claim_pickup_reminder_emails()
RETURNS TABLE (
  email_id uuid,
  recipient_email text,
  customer_name text,
  order_reference text,
  claim_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'claim_pickup_reminder_emails: service role required';
  END IF;

  UPDATE public.pickup_reminder_email_outbox AS outbox
  SET failed_at = now(),
      locked_until = NULL,
      claim_token = NULL,
      last_error = coalesce(
        outbox.last_error,
        'Email delivery worker stopped before completing its final attempt'
      )
  WHERE outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL
    AND outbox.attempts >= 8
    AND (outbox.locked_until IS NULL OR outbox.locked_until < now());

  UPDATE public.pickup_reminder_email_outbox AS outbox
  SET cancelled_at = now(),
      locked_until = NULL,
      claim_token = NULL,
      last_error = 'Order is no longer eligible for a pickup reminder'
  WHERE outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL
    AND (outbox.locked_until IS NULL OR outbox.locked_until < now())
    AND EXISTS (
      SELECT 1
      FROM public.orders AS order_row
      WHERE order_row.id = outbox.order_id
        AND (
          order_row.order_status <> 'Ready for Pickup'
          OR order_row.picked_up_at IS NOT NULL
        )
    );

  RETURN QUERY
  WITH due AS (
    SELECT outbox.id
    FROM public.pickup_reminder_email_outbox AS outbox
    WHERE outbox.sent_at IS NULL
      AND outbox.failed_at IS NULL
      AND outbox.cancelled_at IS NULL
      AND outbox.attempts < 8
      AND outbox.next_attempt_at <= now()
      AND (outbox.locked_until IS NULL OR outbox.locked_until < now())
      AND EXISTS (
        SELECT 1
        FROM public.orders AS order_row
        WHERE order_row.id = outbox.order_id
          AND order_row.order_status = 'Ready for Pickup'
          AND order_row.picked_up_at IS NULL
      )
    ORDER BY outbox.created_at, outbox.id
    LIMIT 20
    FOR UPDATE SKIP LOCKED
  ),
  claimed AS (
    UPDATE public.pickup_reminder_email_outbox AS outbox
    SET attempts = outbox.attempts + 1,
        claim_token = gen_random_uuid(),
        locked_until = now() + interval '10 minutes'
    FROM due
    WHERE outbox.id = due.id
    RETURNING outbox.id, outbox.recipient_email, outbox.customer_name,
              outbox.order_reference, outbox.claim_token
  )
  SELECT claimed.id, claimed.recipient_email, claimed.customer_name,
         claimed.order_reference, claimed.claim_token
  FROM claimed;
END;
$function$;

ALTER FUNCTION public.claim_pickup_reminder_emails() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.claim_pickup_reminder_emails()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_pickup_reminder_emails()
  TO service_role;

CREATE OR REPLACE FUNCTION public.finish_pickup_reminder_email(
  p_email_id uuid,
  p_claim_token uuid,
  p_success boolean,
  p_error text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'finish_pickup_reminder_email: service role required';
  END IF;
  IF p_success IS NULL THEN
    RAISE EXCEPTION 'Email delivery result is required';
  END IF;

  UPDATE public.pickup_reminder_email_outbox AS outbox
  SET sent_at = CASE WHEN p_success THEN now() ELSE NULL END,
      failed_at = CASE
        WHEN NOT p_success AND outbox.attempts >= 8 THEN now()
        ELSE NULL
      END,
      next_attempt_at = CASE
        WHEN p_success THEN outbox.next_attempt_at
        ELSE now() + LEAST(60, power(2, outbox.attempts)::integer)
          * interval '1 minute'
      END,
      last_error = CASE
        WHEN p_success THEN NULL
        ELSE left(coalesce(p_error, 'Email delivery failed'), 1000)
      END,
      claim_token = NULL,
      locked_until = NULL
  WHERE outbox.id = p_email_id
    AND outbox.claim_token = p_claim_token
    AND outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pickup reminder email claim not found or expired';
  END IF;
END;
$function$;

ALTER FUNCTION public.finish_pickup_reminder_email(uuid, uuid, boolean, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.finish_pickup_reminder_email(
  uuid, uuid, boolean, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finish_pickup_reminder_email(
  uuid, uuid, boolean, text
) TO service_role;

COMMIT;
