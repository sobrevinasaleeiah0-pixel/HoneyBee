BEGIN;

CREATE TABLE public.customer_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL
    REFERENCES public.customers(id) ON DELETE CASCADE,
  order_id uuid
    REFERENCES public.orders(id) ON DELETE RESTRICT,
  type text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_at timestamptz,
  CONSTRAINT customer_notifications_pickup_type
    CHECK (type = 'PICKUP_READY_REMINDER'),
  CONSTRAINT customer_notifications_order_type_unique
    UNIQUE (type, order_id)
);

ALTER TABLE public.customer_notifications OWNER TO postgres;
ALTER TABLE public.customer_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.customer_notifications
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.customer_notifications TO authenticated;
GRANT UPDATE (read_at) ON TABLE public.customer_notifications TO authenticated;

CREATE POLICY customer_notifications_read_own
  ON public.customer_notifications FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.customers AS customer
      WHERE customer.id = customer_notifications.customer_id
        AND customer.auth_uid = auth.uid()
        AND customer.status = 'active'
    )
  );

CREATE POLICY customer_notifications_update_own
  ON public.customer_notifications FOR UPDATE
  USING (
    EXISTS (
      SELECT 1
      FROM public.customers AS customer
      WHERE customer.id = customer_notifications.customer_id
        AND customer.auth_uid = auth.uid()
        AND customer.status = 'active'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.customers AS customer
      WHERE customer.id = customer_notifications.customer_id
        AND customer.auth_uid = auth.uid()
        AND customer.status = 'active'
    )
  );

CREATE INDEX idx_customer_notifications_unread
  ON public.customer_notifications (customer_id, created_at DESC)
  WHERE read_at IS NULL;

CREATE TABLE public.customer_fcm_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL
    REFERENCES public.customers(id) ON DELETE CASCADE,
  installation_id uuid NOT NULL,
  fcm_token text NOT NULL UNIQUE,
  platform text NOT NULL CHECK (platform = 'android'),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.customer_fcm_devices OWNER TO postgres;
ALTER TABLE public.customer_fcm_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.customer_fcm_devices
  FROM PUBLIC, anon, authenticated, service_role;

CREATE UNIQUE INDEX idx_customer_fcm_devices_active_installation
  ON public.customer_fcm_devices (customer_id, installation_id)
  WHERE is_active;

CREATE TABLE public.customer_push_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL
    REFERENCES public.customer_notifications(id) ON DELETE CASCADE,
  device_id uuid NOT NULL
    REFERENCES public.customer_fcm_devices(id) ON DELETE RESTRICT,
  customer_id uuid NOT NULL
    REFERENCES public.customers(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  claim_token uuid,
  locked_until timestamptz,
  sent_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  last_error text,
  CONSTRAINT customer_push_outbox_notification_device_unique
    UNIQUE (notification_id, device_id),
  CONSTRAINT customer_push_outbox_single_terminal_state
    CHECK (num_nonnulls(sent_at, failed_at, cancelled_at) <= 1)
);

ALTER TABLE public.customer_push_outbox OWNER TO postgres;
ALTER TABLE public.customer_push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.customer_push_outbox
  FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX idx_customer_push_outbox_pending
  ON public.customer_push_outbox (next_attempt_at, created_at)
  WHERE sent_at IS NULL AND failed_at IS NULL AND cancelled_at IS NULL;

CREATE OR REPLACE FUNCTION public.register_customer_fcm_device(
  p_fcm_token text,
  p_installation_id uuid,
  p_platform text DEFAULT 'android'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_customer_id uuid;
  v_device_id uuid;
  v_token text := NULLIF(btrim(p_fcm_token), '');
BEGIN
  IF auth.uid() IS NULL OR public.is_active_admin() THEN
    RAISE EXCEPTION 'Authenticated customer access is required';
  END IF;
  IF p_installation_id IS NULL OR p_platform IS DISTINCT FROM 'android' THEN
    RAISE EXCEPTION 'A valid Android installation is required';
  END IF;
  IF v_token IS NULL OR length(v_token) > 4096 THEN
    RAISE EXCEPTION 'A valid FCM registration token is required';
  END IF;

  SELECT customer.id INTO v_customer_id
  FROM public.customers AS customer
  WHERE customer.auth_uid = auth.uid()
    AND customer.status = 'active';

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'An active customer profile is required';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(v_token, 0));
  PERFORM pg_advisory_xact_lock(
    hashtextextended(v_customer_id::text || ':' || p_installation_id::text, 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.customer_fcm_devices AS device
    WHERE device.fcm_token = v_token
      AND device.is_active
      AND device.customer_id <> v_customer_id
  ) THEN
    RAISE EXCEPTION 'This FCM token is already active on another account';
  END IF;

  UPDATE public.customer_fcm_devices AS device
  SET is_active = false,
      updated_at = now()
  WHERE device.is_active
    AND device.customer_id = v_customer_id
    AND device.installation_id = p_installation_id
    AND device.fcm_token <> v_token;

  UPDATE public.customer_push_outbox AS outbox
  SET cancelled_at = now(),
      claim_token = NULL,
      locked_until = NULL,
      last_error = 'Device registration changed'
  WHERE outbox.device_id IN (
    SELECT device.id
    FROM public.customer_fcm_devices AS device
    WHERE NOT device.is_active
      AND (
        (device.customer_id = v_customer_id
          AND device.installation_id = p_installation_id
          AND device.fcm_token <> v_token)
        OR device.fcm_token = v_token
      )
  )
    AND outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL;

  INSERT INTO public.customer_fcm_devices (
    customer_id, installation_id, fcm_token, platform, is_active, updated_at
  )
  VALUES (
    v_customer_id, p_installation_id, v_token, p_platform, true, now()
  )
  ON CONFLICT (fcm_token) DO UPDATE
  SET customer_id = EXCLUDED.customer_id,
      installation_id = EXCLUDED.installation_id,
      platform = EXCLUDED.platform,
      is_active = true,
      updated_at = now()
  RETURNING id INTO v_device_id;

  INSERT INTO public.customer_push_outbox (
    notification_id, device_id, customer_id
  )
  SELECT notification.id, v_device_id, v_customer_id
  FROM public.customer_notifications AS notification
  JOIN public.orders AS order_row
    ON order_row.id = notification.order_id
   AND order_row.customer_id = v_customer_id
  WHERE notification.customer_id = v_customer_id
    AND notification.type = 'PICKUP_READY_REMINDER'
    AND notification.read_at IS NULL
    AND order_row.order_status = 'Ready for Pickup'
    AND order_row.picked_up_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.customer_push_outbox AS prior_push
      WHERE prior_push.notification_id = notification.id
        AND prior_push.sent_at IS NOT NULL
    )
  ON CONFLICT (notification_id, device_id) DO NOTHING;

  RETURN v_device_id;
END;
$function$;

ALTER FUNCTION public.register_customer_fcm_device(text, uuid, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.register_customer_fcm_device(text, uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_customer_fcm_device(text, uuid, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.unregister_customer_fcm_device(
  p_installation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_customer_id uuid;
BEGIN
  IF auth.uid() IS NULL OR public.is_active_admin() THEN
    RAISE EXCEPTION 'Authenticated customer access is required';
  END IF;
  IF p_installation_id IS NULL THEN
    RAISE EXCEPTION 'An installation ID is required';
  END IF;

  SELECT customer.id INTO v_customer_id
  FROM public.customers AS customer
  WHERE customer.auth_uid = auth.uid()
    AND customer.status = 'active';

  IF v_customer_id IS NULL THEN
    RAISE EXCEPTION 'An active customer profile is required';
  END IF;

  UPDATE public.customer_fcm_devices AS device
  SET is_active = false,
      updated_at = now()
  WHERE device.customer_id = v_customer_id
    AND device.installation_id = p_installation_id
    AND device.is_active;

  UPDATE public.customer_push_outbox AS outbox
  SET cancelled_at = now(),
      claim_token = NULL,
      locked_until = NULL,
      last_error = 'Device was unregistered'
  WHERE outbox.device_id IN (
    SELECT device.id
    FROM public.customer_fcm_devices AS device
    WHERE device.customer_id = v_customer_id
      AND device.installation_id = p_installation_id
      AND NOT device.is_active
  )
    AND outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL;
END;
$function$;

ALTER FUNCTION public.unregister_customer_fcm_device(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.unregister_customer_fcm_device(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unregister_customer_fcm_device(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_customer_notification_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  INSERT INTO public.customer_push_outbox (
    notification_id, device_id, customer_id
  )
  SELECT NEW.id, device.id, NEW.customer_id
  FROM public.customer_fcm_devices AS device
  WHERE device.customer_id = NEW.customer_id
    AND device.is_active
  ON CONFLICT (notification_id, device_id) DO NOTHING;

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.enqueue_customer_notification_push() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.enqueue_customer_notification_push()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER customer_notifications_enqueue_push
  AFTER INSERT ON public.customer_notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.enqueue_customer_notification_push();

CREATE OR REPLACE FUNCTION public.create_customer_pickup_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  INSERT INTO public.customer_notifications (
    customer_id, order_id, type, title, body
  )
  SELECT customer.id,
         order_row.id,
         'PICKUP_READY_REMINDER',
         'Honeybee Center pickup reminder',
         'Your order is ready for store pickup. Tap to view your order.'
  FROM public.orders AS order_row
  JOIN public.customers AS customer
    ON customer.id = order_row.customer_id
  WHERE order_row.id = NEW.order_id
    AND customer.status = 'active'
    AND customer.auth_uid IS NOT NULL
  ON CONFLICT (type, order_id) DO NOTHING;

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.create_customer_pickup_notification() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_customer_pickup_notification()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER pickup_followups_create_customer_notification
  AFTER INSERT ON public.pickup_followups
  FOR EACH ROW
  EXECUTE FUNCTION public.create_customer_pickup_notification();

CREATE OR REPLACE FUNCTION public.cancel_ineligible_customer_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.order_status <> 'Ready for Pickup' OR NEW.picked_up_at IS NOT NULL THEN
    UPDATE public.customer_push_outbox AS outbox
    SET cancelled_at = now(),
        claim_token = NULL,
        locked_until = NULL,
        last_error = 'Order is no longer eligible for a pickup reminder'
    FROM public.customer_notifications AS notification
    WHERE notification.id = outbox.notification_id
      AND notification.order_id = NEW.id
      AND notification.type = 'PICKUP_READY_REMINDER'
      AND outbox.sent_at IS NULL
      AND outbox.failed_at IS NULL
      AND outbox.cancelled_at IS NULL;
  END IF;

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.cancel_ineligible_customer_push() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.cancel_ineligible_customer_push()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER orders_cancel_ineligible_customer_push
  AFTER UPDATE OF order_status, picked_up_at ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.cancel_ineligible_customer_push();

CREATE OR REPLACE FUNCTION public.cancel_ineligible_customer_device_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF NEW.auth_uid IS DISTINCT FROM OLD.auth_uid
    OR NEW.status <> 'active'
    OR NEW.auth_uid IS NULL
    OR NULLIF(btrim(NEW.email), '') IS NULL
  THEN
    UPDATE public.customer_fcm_devices AS device
    SET is_active = false,
        updated_at = now()
    WHERE device.customer_id = NEW.id
      AND device.is_active;

    UPDATE public.customer_push_outbox AS outbox
    SET cancelled_at = now(),
        claim_token = NULL,
        locked_until = NULL,
        last_error = 'Customer is no longer eligible for push delivery'
    WHERE outbox.customer_id = NEW.id
      AND outbox.sent_at IS NULL
      AND outbox.failed_at IS NULL
      AND outbox.cancelled_at IS NULL;
  END IF;

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.cancel_ineligible_customer_device_push()
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.cancel_ineligible_customer_device_push()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER customers_cancel_ineligible_customer_push
  AFTER UPDATE OF status, auth_uid, email ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.cancel_ineligible_customer_device_push();

CREATE OR REPLACE FUNCTION public.claim_customer_push_notifications()
RETURNS TABLE (
  push_id uuid,
  notification_id uuid,
  device_id uuid,
  fcm_token text,
  title text,
  body text,
  claim_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'claim_customer_push_notifications: service role required';
  END IF;

  UPDATE public.customer_push_outbox AS outbox
  SET failed_at = now(),
      claim_token = NULL,
      locked_until = NULL,
      last_error = coalesce(
        outbox.last_error,
        'Push worker stopped before completing its final attempt'
      )
  WHERE outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL
    AND outbox.attempts >= 8
    AND (outbox.locked_until IS NULL OR outbox.locked_until < now());

  UPDATE public.customer_push_outbox AS outbox
  SET cancelled_at = now(),
      claim_token = NULL,
      locked_until = NULL,
      last_error = 'Order or device is no longer eligible for push delivery'
  WHERE outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL
    AND (outbox.locked_until IS NULL OR outbox.locked_until < now())
    AND (
      NOT EXISTS (
        SELECT 1
        FROM public.customer_fcm_devices AS device
        WHERE device.id = outbox.device_id
          AND device.customer_id = outbox.customer_id
          AND device.is_active
      )
      OR EXISTS (
        SELECT 1
        FROM public.customer_notifications AS notification
        JOIN public.orders AS order_row
          ON order_row.id = notification.order_id
        WHERE notification.id = outbox.notification_id
          AND notification.type = 'PICKUP_READY_REMINDER'
          AND (
            order_row.order_status <> 'Ready for Pickup'
            OR order_row.picked_up_at IS NOT NULL
          )
      )
    );

  RETURN QUERY
  WITH due AS (
    SELECT outbox.id
    FROM public.customer_push_outbox AS outbox
    JOIN public.customer_notifications AS notification
      ON notification.id = outbox.notification_id
     AND notification.customer_id = outbox.customer_id
    JOIN public.customer_fcm_devices AS device
      ON device.id = outbox.device_id
     AND device.customer_id = outbox.customer_id
    WHERE outbox.sent_at IS NULL
      AND outbox.failed_at IS NULL
      AND outbox.cancelled_at IS NULL
      AND outbox.attempts < 8
      AND outbox.next_attempt_at <= now()
      AND (outbox.locked_until IS NULL OR outbox.locked_until < now())
      AND device.is_active
      AND (
        notification.order_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM public.orders AS order_row
          WHERE order_row.id = notification.order_id
            AND order_row.order_status = 'Ready for Pickup'
            AND order_row.picked_up_at IS NULL
        )
      )
    ORDER BY outbox.created_at, outbox.id
    LIMIT 100
    FOR UPDATE OF outbox SKIP LOCKED
  ),
  claimed AS (
    UPDATE public.customer_push_outbox AS outbox
    SET attempts = outbox.attempts + 1,
        claim_token = gen_random_uuid(),
        locked_until = now() + interval '10 minutes'
    FROM due
    WHERE outbox.id = due.id
    RETURNING outbox.id, outbox.notification_id, outbox.device_id,
              outbox.customer_id, outbox.claim_token
  )
  SELECT claimed.id,
         notification.id,
         device.id,
         device.fcm_token,
         notification.title,
         notification.body,
         claimed.claim_token
  FROM claimed
  JOIN public.customer_notifications AS notification
    ON notification.id = claimed.notification_id
   AND notification.customer_id = claimed.customer_id
  JOIN public.customer_fcm_devices AS device
    ON device.id = claimed.device_id
   AND device.customer_id = claimed.customer_id;
END;
$function$;

ALTER FUNCTION public.claim_customer_push_notifications() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.claim_customer_push_notifications()
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.claim_customer_push_notifications()
  TO service_role;

CREATE OR REPLACE FUNCTION public.validate_customer_push_notification_claim(
  p_push_id uuid,
  p_claim_token uuid
)
RETURNS TABLE (
  push_id uuid,
  notification_id uuid,
  device_id uuid,
  fcm_token text,
  title text,
  body text,
  claim_token uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION
      'validate_customer_push_notification_claim: service role required';
  END IF;

  UPDATE public.customer_push_outbox AS outbox
  SET cancelled_at = now(),
      claim_token = NULL,
      locked_until = NULL,
      last_error = 'Order, customer, or device is no longer eligible'
  WHERE outbox.id = p_push_id
    AND outbox.claim_token = p_claim_token
    AND outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL
    AND (
      NOT EXISTS (
        SELECT 1
        FROM public.customer_fcm_devices AS device
        WHERE device.id = outbox.device_id
          AND device.customer_id = outbox.customer_id
          AND device.is_active
      )
      OR NOT EXISTS (
        SELECT 1
        FROM public.customers AS customer
        WHERE customer.id = outbox.customer_id
          AND customer.status = 'active'
          AND customer.auth_uid IS NOT NULL
          AND NULLIF(btrim(customer.email), '') IS NOT NULL
      )
      OR NOT EXISTS (
        SELECT 1
        FROM public.customer_notifications AS notification
        JOIN public.orders AS order_row
          ON order_row.id = notification.order_id
        WHERE notification.id = outbox.notification_id
          AND notification.customer_id = outbox.customer_id
          AND notification.type = 'PICKUP_READY_REMINDER'
          AND order_row.customer_id = outbox.customer_id
          AND order_row.order_status = 'Ready for Pickup'
          AND order_row.picked_up_at IS NULL
      )
    );

  RETURN QUERY
  SELECT outbox.id,
         notification.id,
         device.id,
         device.fcm_token,
         notification.title,
         notification.body,
         outbox.claim_token
  FROM public.customer_push_outbox AS outbox
  JOIN public.customer_notifications AS notification
    ON notification.id = outbox.notification_id
   AND notification.customer_id = outbox.customer_id
  JOIN public.customer_fcm_devices AS device
    ON device.id = outbox.device_id
   AND device.customer_id = outbox.customer_id
  JOIN public.customers AS customer
    ON customer.id = outbox.customer_id
  JOIN public.orders AS order_row
    ON order_row.id = notification.order_id
   AND order_row.customer_id = outbox.customer_id
  WHERE outbox.id = p_push_id
    AND outbox.claim_token = p_claim_token
    AND outbox.locked_until > now()
    AND outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL
    AND device.is_active
    AND customer.status = 'active'
    AND customer.auth_uid IS NOT NULL
    AND NULLIF(btrim(customer.email), '') IS NOT NULL
    AND notification.type = 'PICKUP_READY_REMINDER'
    AND order_row.order_status = 'Ready for Pickup'
    AND order_row.picked_up_at IS NULL;
END;
$function$;

ALTER FUNCTION public.validate_customer_push_notification_claim(uuid, uuid)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.validate_customer_push_notification_claim(
  uuid, uuid
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.validate_customer_push_notification_claim(
  uuid, uuid
) TO service_role;

CREATE OR REPLACE FUNCTION public.finish_customer_push_notification(
  p_push_id uuid,
  p_claim_token uuid,
  p_success boolean,
  p_permanent boolean DEFAULT false,
  p_invalid_token boolean DEFAULT false,
  p_error text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_device_id uuid;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'finish_customer_push_notification: service role required';
  END IF;
  IF p_success IS NULL
    OR p_permanent IS NULL
    OR p_invalid_token IS NULL
    OR (p_success AND (p_permanent OR p_invalid_token))
    OR (p_invalid_token AND NOT p_permanent)
  THEN
    RAISE EXCEPTION 'Invalid push delivery result';
  END IF;

  SELECT outbox.device_id INTO v_device_id
  FROM public.customer_push_outbox AS outbox
  WHERE outbox.id = p_push_id
    AND outbox.claim_token = p_claim_token
    AND outbox.locked_until > now()
    AND outbox.sent_at IS NULL
    AND outbox.failed_at IS NULL
    AND outbox.cancelled_at IS NULL
  FOR UPDATE;

  IF v_device_id IS NULL THEN
    RAISE EXCEPTION 'Customer push claim not found or expired';
  END IF;

  UPDATE public.customer_push_outbox AS outbox
  SET sent_at = CASE WHEN p_success THEN now() ELSE NULL END,
      failed_at = CASE
        WHEN NOT p_success AND (p_permanent OR outbox.attempts >= 8)
          THEN now()
        ELSE NULL
      END,
      next_attempt_at = CASE
        WHEN p_success OR p_permanent THEN outbox.next_attempt_at
        ELSE now() + LEAST(360, power(2, outbox.attempts)::integer)
          * interval '1 minute'
      END,
      last_error = CASE
        WHEN p_success THEN NULL
        ELSE left(coalesce(p_error, 'FCM delivery failed'), 500)
      END,
      claim_token = NULL,
      locked_until = NULL
  WHERE outbox.id = p_push_id
    AND outbox.claim_token = p_claim_token;

  IF p_invalid_token THEN
    UPDATE public.customer_fcm_devices AS device
    SET is_active = false,
        updated_at = now()
    WHERE device.id = v_device_id;

    UPDATE public.customer_push_outbox AS outbox
    SET cancelled_at = now(),
        claim_token = NULL,
        locked_until = NULL,
        last_error = 'Device token is invalid or unregistered'
    WHERE outbox.device_id = v_device_id
      AND outbox.id <> p_push_id
      AND outbox.sent_at IS NULL
      AND outbox.failed_at IS NULL
      AND outbox.cancelled_at IS NULL
      AND (outbox.locked_until IS NULL OR outbox.locked_until < now());
  END IF;
END;
$function$;

ALTER FUNCTION public.finish_customer_push_notification(
  uuid, uuid, boolean, boolean, boolean, text
) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.finish_customer_push_notification(
  uuid, uuid, boolean, boolean, boolean, text
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.finish_customer_push_notification(
  uuid, uuid, boolean, boolean, boolean, text
) TO service_role;

DO $publication$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'customer_notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime
      ADD TABLE public.customer_notifications;
  END IF;
END;
$publication$;

COMMIT;
