# Customer App push notification contract

This contract describes the Supabase backend interface for the separate
Honeybee Center Customer App. The client must use its current Supabase Auth
session. It must never submit a `customer_id` as proof of identity.

## Register or refresh a device token

After sign-in and notification permission are granted, obtain the current FCM
token and call the authenticated Supabase RPC:

```text
register_customer_fcm_device(
  p_fcm_token: string,
  p_installation_id: UUID,
  p_platform: "android"
) -> UUID
```

`p_platform` defaults to `android`. Generate and persist a random installation
UUID in app-private storage. Send the FCM token whenever it is first available
and whenever Firebase reports a refreshed token. The RPC resolves the active
customer from `auth.uid()` and `customers.auth_uid`; it rejects admin accounts
and does not accept a customer ID.

On sign-out, call:

```text
unregister_customer_fcm_device(
  p_installation_id: UUID
) -> void
```

Use the signed-in Supabase session for this call before clearing it. If the
session is already gone, the server-side customer ownership check intentionally
rejects the request; do not replace it with an unauthenticated token deletion
endpoint.

## List and update customer notifications

Use the authenticated Supabase client. RLS associates rows with the active
customer mapped from `auth.uid()`.

List newest first, selecting only the fields needed by the UI:

```text
customer_notifications:
  id, order_id, type, title, body, created_at, read_at
```

Example query:

```dart
supabase
  .from('customer_notifications')
  .select('id, order_id, type, title, body, created_at, read_at')
  .order('created_at', ascending: false);
```

For an unread badge, count rows where `read_at IS NULL`. Mark one row read with
an update of `read_at` only, filtered by its notification ID. RLS restricts
both operations to the authenticated customer's rows; direct inserts and
deletes are not granted.

## Push payload

The FCM HTTP v1 message contains:

```json
{
  "notification": {
    "title": "Honeybee Center pickup reminder",
    "body": "Your order is ready for store pickup. Tap to view your order."
  },
  "data": {
    "notification_id": "<customer_notifications.id UUID>",
    "type": "PICKUP_READY_REMINDER"
  },
  "android": {
    "priority": "HIGH",
    "notification": {
      "channel_id": "pickup_reminders",
      "tag": "customer-notification-<notification UUID>"
    }
  }
}
```

The push deliberately contains neither a customer ID nor an order ID. Do not
add either as a trusted routing value.

## Safe notification taps

1. Require an authenticated customer session.
2. Load the notification by `notification_id` from
   `customer_notifications`; RLS must return only the customer's row.
3. If it has an `order_id`, resolve that order through an authenticated,
   customer-scoped lookup (the existing `get_my_customer_orders()` RPC returns
   the signed-in customer's orders). Match the ID in that result before
   navigating.
4. If the notification or owned order cannot be loaded, show a safe fallback
   (for example, open the notification list); never render order details from
   the FCM payload alone.
5. Mark the notification read through the authenticated update after it has
   been displayed or opened.

Request Android notification permission on Android 13 and later, create the
`pickup_reminders` channel, and handle foreground, background, and terminated
app delivery/taps. A denied permission must not prevent the in-app notification
from being stored and listed.
