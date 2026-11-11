BEGIN;

GRANT SELECT, UPDATE ON public.notifications TO authenticated;
REVOKE INSERT, DELETE ON public.notifications FROM authenticated, anon;

DROP POLICY IF EXISTS "notifications_read_admin" ON public.notifications;
DROP POLICY IF EXISTS "notifications_update_admin" ON public.notifications;

CREATE POLICY "notifications_read_admin"
  ON public.notifications FOR SELECT
  USING (public.is_active_admin());

CREATE POLICY "notifications_update_admin"
  ON public.notifications FOR UPDATE
  USING (public.is_active_admin())
  WITH CHECK (public.is_active_admin());

CREATE OR REPLACE FUNCTION public.notify_admin_of_new_customer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  INSERT INTO public.notifications (type, message, related_id)
  VALUES (
    'NEW_CUSTOMER',
    'New customer registered: ' || NEW.name || '.',
    NEW.id::text
  )
  ON CONFLICT (type, related_id) WHERE is_read = false
  DO NOTHING;

  RETURN NEW;
END;
$function$;

ALTER FUNCTION public.notify_admin_of_new_customer() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.notify_admin_of_new_customer()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS customers_notify_admin_after_insert
  ON public.customers;
CREATE TRIGGER customers_notify_admin_after_insert
  AFTER INSERT ON public.customers
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_admin_of_new_customer();

CREATE OR REPLACE FUNCTION public.create_admin_notification(
  p_type text,
  p_message text,
  p_related_id text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
  IF NOT public.is_active_admin() THEN
    RAISE EXCEPTION 'Active administrator access required';
  END IF;

  IF p_type IS NULL OR p_type NOT IN (
    'OUT_OF_STOCK',
    'LOW_STOCK',
    'PRODUCTION_COMPLETED',
    'NEW_SALE',
    'PAYMENT_VERIFIED',
    'PAYMENT_REJECTED',
    'SCAN_MISMATCH',
    'BOTTLE_LOW_STOCK',
    'PICKUP_REMINDER_SENT',
    'ORDER_PICKED_UP',
    'NEW_ORDER'
  ) THEN
    RAISE EXCEPTION 'Unsupported notification type';
  END IF;

  IF p_message IS NULL
    OR nullif(btrim(p_message), '') IS NULL
    OR length(p_message) > 1000
  THEN
    RAISE EXCEPTION 'Notification message must contain 1 to 1000 characters';
  END IF;

  INSERT INTO public.notifications (type, message, related_id)
  VALUES (p_type, btrim(p_message), p_related_id)
  ON CONFLICT (type, related_id) WHERE is_read = false
  DO NOTHING;
END;
$function$;

ALTER FUNCTION public.create_admin_notification(text, text, text)
  OWNER TO postgres;
REVOKE ALL ON FUNCTION public.create_admin_notification(text, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_admin_notification(text, text, text)
  TO authenticated;

DO $publication$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END;
$publication$;

COMMIT;
