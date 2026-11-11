-- Server-side customer messaging for due pickup follow-ups.
-- Apply only after the customer_messaging migration is deployed.
BEGIN;

CREATE TABLE public.pickup_followup_settings (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  enabled boolean NOT NULL DEFAULT true,
  delay interval NOT NULL DEFAULT interval '24 hours'
    CHECK (delay > interval '0 seconds'),
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.pickup_followup_settings (singleton, enabled, delay)
VALUES (true, true, interval '24 hours')
ON CONFLICT (singleton) DO NOTHING;

ALTER TABLE public.pickup_followup_settings OWNER TO postgres;
ALTER TABLE public.pickup_followup_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pickup_followup_settings
  FROM PUBLIC, anon, authenticated, service_role;

CREATE TABLE public.pickup_followups (
  order_id uuid PRIMARY KEY
    REFERENCES public.orders(id) ON DELETE RESTRICT,
  conversation_id uuid NOT NULL
    REFERENCES public.conversations(id) ON DELETE RESTRICT,
  message_id uuid NOT NULL
    REFERENCES public.messages(id) ON DELETE RESTRICT,
  sent_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.pickup_followups OWNER TO postgres;
ALTER TABLE public.pickup_followups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pickup_followups
  FROM PUBLIC, anon, authenticated, service_role;

CREATE INDEX idx_orders_due_pickup_followups
  ON public.orders (ready_for_pickup_at)
  WHERE order_status = 'Ready for Pickup'
    AND picked_up_at IS NULL
    AND pickup_reminder_sent = false;

REVOKE ALL ON FUNCTION public.create_customer_conversation(uuid)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.start_customer_conversation(
  p_message text,
  p_order_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_customer public.customers%ROWTYPE;
  v_conversation_id uuid;
  v_body text := coalesce(btrim(p_message), '');
BEGIN
  SELECT * INTO v_customer
  FROM public.customers
  WHERE auth_uid = auth.uid()
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'An active customer profile is required';
  END IF;
  IF NULLIF(btrim(v_customer.email), '') IS NULL THEN
    RAISE EXCEPTION 'A customer email is required to start a conversation';
  END IF;
  IF v_body = '' THEN
    RAISE EXCEPTION 'The first customer message cannot be empty';
  END IF;
  IF p_order_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.orders
    WHERE id = p_order_id
      AND customer_id = v_customer.id
  ) THEN
    RAISE EXCEPTION 'Order not found for this customer';
  END IF;

  SELECT id INTO v_conversation_id
  FROM public.conversations
  WHERE customer_id = v_customer.id
    AND order_id IS NOT DISTINCT FROM p_order_id
    AND status <> 'resolved'
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_conversation_id IS NULL THEN
    BEGIN
      INSERT INTO public.conversations (
        customer_id, customer_name, customer_email, order_id, status,
        last_message, is_read
      )
      VALUES (
        v_customer.id, v_customer.name, v_customer.email, p_order_id,
        'open', v_body, false
      )
      RETURNING id INTO v_conversation_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO v_conversation_id
      FROM public.conversations
      WHERE customer_id = v_customer.id
        AND order_id IS NOT DISTINCT FROM p_order_id
        AND status <> 'resolved'
      ORDER BY updated_at DESC
      LIMIT 1;

      IF v_conversation_id IS NULL THEN
        RAISE;
      END IF;
    END;
  END IF;

  INSERT INTO public.messages (
    conversation_id, message, sender_id, sender_role, sender_name, is_read
  )
  VALUES (
    v_conversation_id, v_body, auth.uid()::text, 'customer',
    v_customer.name, false
  );

  UPDATE public.conversations
  SET last_message = v_body,
      is_read = false,
      status = 'open',
      updated_at = now()
  WHERE id = v_conversation_id;

  RETURN v_conversation_id;
END;
$function$;

ALTER FUNCTION public.start_customer_conversation(text, uuid)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.start_customer_conversation(text, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_customer_conversation(text, uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.process_due_pickup_followups()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_settings public.pickup_followup_settings%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_customer public.customers%ROWTYPE;
  v_conversation_id uuid;
  v_message_id uuid;
  v_message text;
  v_order_label text;
  v_sent integer := 0;
BEGIN
  SELECT * INTO v_settings
  FROM public.pickup_followup_settings
  WHERE singleton = true;

  IF NOT FOUND OR NOT v_settings.enabled THEN
    RETURN 0;
  END IF;

  FOR v_order IN
    SELECT order_row.*
    FROM public.orders AS order_row
    JOIN public.customers AS customer
      ON customer.id = order_row.customer_id
    WHERE order_row.order_status = 'Ready for Pickup'
      AND order_row.ready_for_pickup_at IS NOT NULL
      AND order_row.ready_for_pickup_at <= now() - v_settings.delay
      AND order_row.picked_up_at IS NULL
      AND order_row.pickup_reminder_sent = false
      AND customer.status = 'active'
      AND customer.auth_uid IS NOT NULL
      AND NULLIF(btrim(customer.email), '') IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.pickup_followups AS followup
        WHERE followup.order_id = order_row.id
      )
    ORDER BY order_row.ready_for_pickup_at, order_row.id
    LIMIT 50
    FOR UPDATE OF order_row SKIP LOCKED
  LOOP
    SELECT * INTO v_customer
    FROM public.customers
    WHERE id = v_order.customer_id
      AND status = 'active'
      AND auth_uid IS NOT NULL;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    v_order_label := coalesce(
      nullif(btrim(v_order.order_reference), ''),
      'order ' || v_order.id::text
    );
    v_message := format(
      'Hi %s, your order %s has been ready for pickup for the configured '
      'waiting period. '
      'Please let us know if you need help arranging pickup. Thank you!',
      v_customer.name,
      v_order_label
    );

    SELECT id INTO v_conversation_id
    FROM public.conversations
    WHERE customer_id = v_customer.id
      AND order_id = v_order.id
    ORDER BY (status = 'open') DESC, updated_at DESC
    LIMIT 1
    FOR UPDATE;

    IF v_conversation_id IS NULL THEN
      BEGIN
        INSERT INTO public.conversations (
          customer_id, customer_name, customer_email, order_id, status,
          last_message, is_read
        )
        VALUES (
          v_customer.id, v_customer.name, v_customer.email, v_order.id,
          'open', v_message, false
        )
        RETURNING id INTO v_conversation_id;
      EXCEPTION WHEN unique_violation THEN
        SELECT id INTO v_conversation_id
        FROM public.conversations
        WHERE customer_id = v_customer.id
          AND order_id = v_order.id
        ORDER BY (status = 'open') DESC, updated_at DESC
        LIMIT 1
        FOR UPDATE;

        IF v_conversation_id IS NULL THEN
          RAISE;
        END IF;
      END;
    END IF;

    INSERT INTO public.messages (
      conversation_id, message, sender_id, sender_role, sender_name, is_read
    )
    VALUES (
      v_conversation_id, v_message, 'system', 'system',
      'Honeybee Center · Automatic follow-up', false
    )
    RETURNING id INTO v_message_id;

    UPDATE public.conversations
    SET last_message = v_message,
        status = 'open',
        is_read = false,
        updated_at = now()
    WHERE id = v_conversation_id;

    INSERT INTO public.pickup_followups (
      order_id, conversation_id, message_id
    )
    VALUES (v_order.id, v_conversation_id, v_message_id);

    UPDATE public.orders
    SET pickup_reminder_sent = true,
        pickup_reminder_sent_at = now(),
        updated_at = now()
    WHERE id = v_order.id
      AND order_status = 'Ready for Pickup'
      AND picked_up_at IS NULL
      AND pickup_reminder_sent = false;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Order % became ineligible during follow-up', v_order.id;
    END IF;

    v_sent := v_sent + 1;
  END LOOP;

  RETURN v_sent;
END;
$function$;

ALTER FUNCTION public.process_due_pickup_followups() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.process_due_pickup_followups()
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.get_admin_conversation_inbox()
RETURNS TABLE (
  conversation_id uuid,
  customer_id uuid,
  customer_name text,
  customer_email text,
  customer_phone text,
  customer_address text,
  customer_orders jsonb,
  order_id uuid,
  order_reference text,
  order_status text,
  order_total numeric,
  conversation_status text,
  last_message text,
  last_message_at timestamptz,
  last_sender_role text,
  last_attachment_path text,
  unread_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'get_admin_conversation_inbox: active admin role required';
  END IF;

  RETURN QUERY
  SELECT conversation.id,
         conversation.customer_id,
         conversation.customer_name,
         conversation.customer_email,
         customer.phone,
         customer.address,
         coalesce(customer_orders.items, '[]'::jsonb),
         conversation.order_id,
         order_row.order_reference,
         order_row.order_status,
         order_row.total_amount,
         conversation.status,
         latest.message,
         latest.created_at,
         latest.sender_role,
         latest.attachment_path,
         coalesce(unread.count, 0)
  FROM public.conversations AS conversation
  LEFT JOIN public.customers AS customer
    ON customer.id = conversation.customer_id
  LEFT JOIN public.orders AS order_row
    ON order_row.id = conversation.order_id
  LEFT JOIN LATERAL (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', recent_order.id,
        'reference', recent_order.order_reference,
        'status', recent_order.order_status,
        'total', recent_order.total_amount,
        'created_at', recent_order.created_at
      )
      ORDER BY recent_order.created_at DESC
    ) AS items
    FROM (
      SELECT order_item.id, order_item.order_reference,
             order_item.order_status, order_item.total_amount,
             order_item.created_at
      FROM public.orders AS order_item
      WHERE order_item.customer_id = conversation.customer_id
      ORDER BY
        (order_item.id = conversation.order_id) DESC,
        order_item.created_at DESC
      LIMIT 5
    ) AS recent_order
  ) AS customer_orders ON true
  JOIN LATERAL (
    SELECT message.message, message.created_at, message.sender_role,
           message.attachment_path
    FROM public.messages AS message
    WHERE message.conversation_id = conversation.id
    ORDER BY message.created_at DESC, message.id DESC
    LIMIT 1
  ) AS latest ON true
  LEFT JOIN LATERAL (
    SELECT count(*) AS count
    FROM public.messages AS message
    WHERE message.conversation_id = conversation.id
      AND message.sender_role = 'customer'
      AND message.is_read = false
  ) AS unread ON true
  WHERE EXISTS (
    SELECT 1 FROM public.messages AS customer_message
    WHERE customer_message.conversation_id = conversation.id
      AND customer_message.sender_role = 'customer'
  )
  OR EXISTS (
    SELECT 1 FROM public.pickup_followups AS followup
    WHERE followup.conversation_id = conversation.id
  )
  ORDER BY latest.created_at DESC, conversation.id;
END;
$function$;

ALTER FUNCTION public.get_admin_conversation_inbox() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_admin_conversation_inbox()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_conversation_inbox()
  TO authenticated;

DO $schedule$
DECLARE
  v_job_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_extension
    WHERE extname = 'pg_cron'
  ) OR pg_catalog.to_regnamespace('cron') IS NULL THEN
    RAISE EXCEPTION
      'pg_cron is required; enable the Supabase Cron extension before applying this migration';
  END IF;

  SELECT jobid INTO v_job_id
  FROM cron.job
  WHERE jobname = 'honeybee-center-pickup-followups';

  IF v_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(v_job_id);
  END IF;

  PERFORM cron.schedule(
    'honeybee-center-pickup-followups',
    '*/15 * * * *',
    'SELECT public.process_due_pickup_followups();'
  );
END;
$schedule$;

COMMIT;
