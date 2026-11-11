-- Customer messaging and private attachment support.
BEGIN;

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS attachment_path text,
  ADD COLUMN IF NOT EXISTS attachment_mime_type text;

REVOKE ALL ON TABLE public.conversations, public.messages
  FROM anon, authenticated;
GRANT SELECT ON public.conversations, public.messages TO authenticated;

DROP POLICY IF EXISTS "convs_read_own_customer" ON public.conversations;
DROP POLICY IF EXISTS "msgs_read_own_customer" ON public.messages;
DROP POLICY IF EXISTS "conversation_images_read_authorized" ON storage.objects;
DROP POLICY IF EXISTS "conversation_images_insert_authorized" ON storage.objects;
DROP POLICY IF EXISTS "conversation_images_delete_owner" ON storage.objects;

CREATE POLICY "convs_read_own_customer"
  ON public.conversations FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.customers AS customer
      WHERE customer.id = conversations.customer_id
        AND customer.auth_uid = auth.uid()
        AND customer.status = 'active'
    )
  );

CREATE POLICY "msgs_read_own_customer"
  ON public.messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1
      FROM public.conversations AS conversation
      JOIN public.customers AS customer
        ON customer.id = conversation.customer_id
      WHERE conversation.id = messages.conversation_id
        AND customer.auth_uid = auth.uid()
        AND customer.status = 'active'
    )
  );

DO $bucket$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM storage.buckets AS bucket
    WHERE bucket.id = 'customer-conversation-images'
      AND bucket.public
  ) THEN
    RAISE EXCEPTION 'customer-conversation-images must be a private bucket';
  END IF;
END;
$bucket$;

INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
VALUES (
  'customer-conversation-images',
  'customer-conversation-images',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "conversation_images_read_authorized"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'customer-conversation-images'
    AND (
      public.is_active_admin()
      OR (
        (storage.foldername(objects.name))[1] = auth.uid()::text
        AND EXISTS (
          SELECT 1
          FROM public.conversations AS conversation
          JOIN public.customers AS customer
            ON customer.id = conversation.customer_id
          WHERE conversation.id::text = (storage.foldername(objects.name))[2]
            AND customer.auth_uid = auth.uid()
            AND customer.status = 'active'
        )
      )
      OR (
        (storage.foldername(objects.name))[1] = 'admin'
        AND EXISTS (
          SELECT 1
          FROM public.conversations AS conversation
          JOIN public.customers AS customer
            ON customer.id = conversation.customer_id
          WHERE conversation.id::text = (storage.foldername(objects.name))[3]
            AND customer.auth_uid = auth.uid()
            AND customer.status = 'active'
        )
      )
    )
  );

CREATE POLICY "conversation_images_insert_authorized"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'customer-conversation-images'
    AND (
      (
        (storage.foldername(objects.name))[1] = 'admin'
        AND (storage.foldername(objects.name))[2] = auth.uid()::text
        AND public.get_admin_role() = 'co_admin'
        AND EXISTS (
          SELECT 1 FROM public.conversations AS conversation
          WHERE conversation.id::text = (storage.foldername(objects.name))[3]
        )
      )
      OR (
        (storage.foldername(objects.name))[1] = auth.uid()::text
        AND EXISTS (
          SELECT 1
          FROM public.conversations AS conversation
          JOIN public.customers AS customer
            ON customer.id = conversation.customer_id
          WHERE conversation.id::text = (storage.foldername(objects.name))[2]
            AND customer.auth_uid = auth.uid()
            AND customer.status = 'active'
        )
      )
    )
  );

CREATE POLICY "conversation_images_delete_owner"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'customer-conversation-images'
    AND (
      (
        (storage.foldername(objects.name))[1] = 'admin'
        AND (storage.foldername(objects.name))[2] = auth.uid()::text
        AND public.get_admin_role() = 'co_admin'
      )
      OR (
        (storage.foldername(objects.name))[1] = auth.uid()::text
        AND EXISTS (
          SELECT 1
          FROM public.conversations AS conversation
          JOIN public.customers AS customer
            ON customer.id = conversation.customer_id
          WHERE conversation.id::text = (storage.foldername(objects.name))[2]
            AND customer.auth_uid = auth.uid()
            AND customer.status = 'active'
        )
      )
    )
  );

CREATE OR REPLACE FUNCTION public.create_customer_conversation(
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
BEGIN
  SELECT * INTO v_customer
  FROM public.customers
  WHERE auth_uid = auth.uid()
    AND status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'An active customer profile is required';
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
  WHERE lower(customer_email) = lower(v_customer.email)
    AND customer_id = v_customer.id
    AND order_id IS NOT DISTINCT FROM p_order_id
    AND status <> 'resolved'
  LIMIT 1;

  IF v_conversation_id IS NOT NULL THEN
    RETURN v_conversation_id;
  END IF;

  BEGIN
    INSERT INTO public.conversations (
      customer_id, customer_name, customer_email, order_id, status,
      last_message, is_read
    )
    VALUES (
      v_customer.id, v_customer.name, v_customer.email, p_order_id, 'open',
      '', true
    )
    RETURNING id INTO v_conversation_id;
  EXCEPTION WHEN unique_violation THEN
    SELECT id INTO v_conversation_id
    FROM public.conversations
    WHERE lower(customer_email) = lower(v_customer.email)
      AND customer_id = v_customer.id
      AND order_id IS NOT DISTINCT FROM p_order_id
      AND status <> 'resolved'
    LIMIT 1;

    IF v_conversation_id IS NULL THEN
      RAISE;
    END IF;
  END;

  RETURN v_conversation_id;
END;
$function$;

ALTER FUNCTION public.create_customer_conversation(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_customer_conversation(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_customer_conversation(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.send_customer_message(
  p_conversation_id uuid,
  p_message text,
  p_attachment_path text DEFAULT NULL,
  p_attachment_mime_type text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_customer public.customers%ROWTYPE;
  v_message_id uuid;
  v_body text := coalesce(btrim(p_message), '');
BEGIN
  SELECT customer.* INTO v_customer
  FROM public.customers AS customer
  JOIN public.conversations AS conversation
    ON conversation.customer_id = customer.id
  WHERE conversation.id = p_conversation_id
    AND customer.auth_uid = auth.uid()
    AND customer.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation not found for this customer';
  END IF;

  IF v_body = '' AND p_attachment_path IS NULL THEN
    RAISE EXCEPTION 'Message text or an image attachment is required';
  END IF;
  IF p_attachment_path IS NOT NULL AND (
    p_attachment_path NOT LIKE
      auth.uid()::text || '/' || p_conversation_id::text || '/%'
    OR p_attachment_mime_type IS NULL
    OR p_attachment_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp')
  ) THEN
    RAISE EXCEPTION 'Invalid customer attachment path or type';
  END IF;

  INSERT INTO public.messages (
    conversation_id, message, sender_id, sender_role, sender_name,
    is_read, attachment_path, attachment_mime_type
  )
  VALUES (
    p_conversation_id, v_body, auth.uid()::text, 'customer', v_customer.name,
    false, p_attachment_path, p_attachment_mime_type
  )
  RETURNING id INTO v_message_id;

  UPDATE public.conversations
  SET last_message = CASE
        WHEN v_body <> '' THEN v_body
        ELSE '[Image]'
      END,
      is_read = false,
      status = 'open',
      updated_at = now()
  WHERE id = p_conversation_id;

  RETURN v_message_id;
END;
$function$;

ALTER FUNCTION public.send_customer_message(uuid, text, text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.send_customer_message(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_customer_message(uuid, text, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.send_admin_conversation_message(
  p_conversation_id uuid,
  p_message text,
  p_attachment_path text DEFAULT NULL,
  p_attachment_mime_type text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
  v_admin public.admins%ROWTYPE;
  v_message_id uuid;
  v_body text := coalesce(btrim(p_message), '');
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'send_admin_conversation_message: co_admin role required';
  END IF;

  SELECT * INTO v_admin
  FROM public.admins
  WHERE id = auth.uid()
    AND status = 'active'
    AND role = 'co_admin';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Active Co-Admin profile is required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.conversations
    WHERE id = p_conversation_id
  ) THEN
    RAISE EXCEPTION 'Conversation % not found', p_conversation_id;
  END IF;

  IF v_body = '' AND p_attachment_path IS NULL THEN
    RAISE EXCEPTION 'Message text or an image attachment is required';
  END IF;
  IF p_attachment_path IS NOT NULL AND (
    p_attachment_path NOT LIKE
      'admin/' || auth.uid()::text || '/' || p_conversation_id::text || '/%'
    OR p_attachment_mime_type IS NULL
    OR p_attachment_mime_type NOT IN ('image/jpeg', 'image/png', 'image/webp')
  ) THEN
    RAISE EXCEPTION 'Invalid admin attachment path or type';
  END IF;

  INSERT INTO public.messages (
    conversation_id, message, sender_id, sender_role, sender_name,
    is_read, attachment_path, attachment_mime_type
  )
  VALUES (
    p_conversation_id, v_body, auth.uid()::text, 'co_admin', v_admin.name,
    false, p_attachment_path, p_attachment_mime_type
  )
  RETURNING id INTO v_message_id;

  UPDATE public.conversations
  SET last_message = CASE WHEN v_body <> '' THEN v_body ELSE '[Image]' END,
      updated_at = now()
  WHERE id = p_conversation_id;

  RETURN v_message_id;
END;
$function$;

ALTER FUNCTION public.send_admin_conversation_message(uuid, text, text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.send_admin_conversation_message(uuid, text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_admin_conversation_message(uuid, text, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_admin_conversation_read(
  p_conversation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'mark_admin_conversation_read: active admin role required';
  END IF;

  UPDATE public.messages
  SET is_read = true
  WHERE conversation_id = p_conversation_id
    AND sender_role = 'customer'
    AND is_read = false;

  UPDATE public.conversations
  SET is_read = true
  WHERE id = p_conversation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation % not found', p_conversation_id;
  END IF;
END;
$function$;

ALTER FUNCTION public.mark_admin_conversation_read(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.mark_admin_conversation_read(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_admin_conversation_read(uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_admin_conversation_status(
  p_conversation_id uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF public.get_admin_role() IS DISTINCT FROM 'co_admin' THEN
    RAISE EXCEPTION 'set_admin_conversation_status: co_admin role required';
  END IF;
  IF p_status NOT IN ('open', 'resolved') THEN
    RAISE EXCEPTION 'Conversation status must be open or resolved';
  END IF;

  UPDATE public.conversations
  SET status = p_status,
      updated_at = now()
  WHERE id = p_conversation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Conversation % not found', p_conversation_id;
  END IF;
END;
$function$;

ALTER FUNCTION public.set_admin_conversation_status(uuid, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.set_admin_conversation_status(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_admin_conversation_status(uuid, text)
  TO authenticated;

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
      AND message.sender_role <> 'system'
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
  ORDER BY latest.created_at DESC, conversation.id;
END;
$function$;

ALTER FUNCTION public.get_admin_conversation_inbox() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_admin_conversation_inbox()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_admin_conversation_inbox()
  TO authenticated;

DO $realtime$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    RAISE EXCEPTION 'supabase_realtime publication does not exist';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'conversations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
END;
$realtime$;

COMMIT;
