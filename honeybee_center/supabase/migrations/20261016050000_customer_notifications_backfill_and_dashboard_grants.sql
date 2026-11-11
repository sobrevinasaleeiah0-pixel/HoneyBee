BEGIN;

-- These grants are constrained by the existing admin-only RLS policies.
GRANT SELECT ON public.customers, public.inventory_movements TO authenticated;

-- Backfill customer registrations that predate the after-insert trigger.
-- Use the customer UUID as related_id so this operation is repeatable.
INSERT INTO public.notifications (type, message, related_id, created_at)
SELECT
  'NEW_CUSTOMER',
  'New customer registered: ' || customer.name || '.',
  customer.id::text,
  customer.created_at
FROM public.customers AS customer
WHERE NOT EXISTS (
  SELECT 1
  FROM public.notifications AS notification
  WHERE notification.type = 'NEW_CUSTOMER'
    AND notification.related_id = customer.id::text
)
ON CONFLICT (type, related_id) WHERE is_read = false
DO NOTHING;

COMMIT;
