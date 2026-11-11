import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/services/supabase_notification_service.dart';

void main() {
  group('SupabaseNotificationService.mapRows', () {
    test('maps Supabase notification columns for admin UI', () {
      final mapped = SupabaseNotificationService.mapRows([
        {
          'id': 'notification-id',
          'type': 'NEW_CUSTOMER',
          'message': 'New customer registered: Pat.',
          'related_id': 'customer-id',
          'is_read': false,
          'is_archived': true,
          'created_at': '2026-10-16T00:00:00.000Z',
        },
      ]);

      expect(mapped, hasLength(1));
      expect(mapped.single['id'], 'notification-id');
      expect(mapped.single['type'], 'NEW_CUSTOMER');
      expect(mapped.single['relatedId'], 'customer-id');
      expect(mapped.single['isRead'], isFalse);
      expect(mapped.single['isArchived'], isTrue);
      expect(mapped.single['timestamp'], isA<int>());
    });

    test('ignores malformed rows and handles missing timestamps', () {
      final mapped = SupabaseNotificationService.mapRows([
        'not-a-row',
        {'id': 'notification-id', 'is_read': true},
      ]);

      expect(mapped, hasLength(1));
      expect(mapped.single['id'], 'notification-id');
      expect(mapped.single['isRead'], isTrue);
      expect(mapped.single['timestamp'], 0);
    });
  });
}
