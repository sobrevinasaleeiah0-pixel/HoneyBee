import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/services/conversation_service.dart';

void main() {
  group('ConversationService inbox entries', () {
    test('adds linked customers without conversations', () {
      final inbox = ConversationService.mergeInboxWithLinkedCustomers(
        const [],
        [
          {
            'id': 'customer-1',
            'name': 'Customer One',
            'email': 'one@example.com',
            'phone': '123',
            'address': 'Somewhere',
          },
        ],
        ordersByCustomer: {
          'customer-1': [
            {
              'id': 'order-1',
              'reference': 'HB-001',
              'status': 'Pending',
              'total': 100,
            },
          ],
        },
      );

      expect(inbox, hasLength(1));
      expect(inbox.single['conversation_id'], isNull);
      expect(inbox.single['customer_name'], 'Customer One');
      expect(inbox.single['unread_count'], 0);
      expect(
        (inbox.single['customer_orders'] as List).single['reference'],
        'HB-001',
      );
    });

    test('does not duplicate customers that already have conversations', () {
      final inbox = ConversationService.mergeInboxWithLinkedCustomers(
        [
          {
            'conversation_id': 'conversation-1',
            'customer_id': 'customer-1',
            'customer_name': 'Customer One',
          },
        ],
        [
          {'id': 'customer-1', 'name': 'Customer One'},
          {'id': 'customer-2', 'name': 'Customer Two'},
        ],
      );

      expect(inbox, hasLength(2));
      expect(inbox.map((entry) => entry['customer_id']), [
        'customer-1',
        'customer-2',
      ]);
      expect(inbox.last['conversation_id'], isNull);
    });

    test(
      'enriches conversations with linked order payment and item details',
      () {
        final inbox = ConversationService.mergeInboxWithLinkedCustomers(
          [
            {
              'conversation_id': 'conversation-1',
              'customer_id': 'customer-1',
              'order_id': 'order-1',
            },
          ],
          const [],
          ordersByCustomer: {
            'customer-1': [
              {
                'id': 'order-1',
                'reference': 'HB-001',
                'status': 'Pending',
                'payment_status': 'Pending',
                'payment_method': 'GCash',
                'total': 1450,
                'items': [
                  {'product_name': 'Wildflower Honey', 'quantity': 1},
                ],
              },
            ],
          },
        );

        expect(inbox.single['payment_status'], 'Pending');
        expect(inbox.single['payment_method'], 'GCash');
        expect(inbox.single['customer_orders'], hasLength(1));
        expect(inbox.single['customer_orders'].single['items'], hasLength(1));
      },
    );
  });

  group('ConversationService image validation', () {
    test('accepts supported image types within the upload limit', () {
      expect(
        ConversationService.validateImageUpload(
          mimeType: 'image/jpeg',
          byteLength: 1024,
        ),
        'image/jpeg',
      );
      expect(
        ConversationService.validateImageUpload(
          mimeType: 'image/png',
          byteLength: ConversationService.maxImageBytes,
        ),
        'image/png',
      );
    });

    test('rejects unsupported image types and invalid sizes', () {
      expect(
        () => ConversationService.validateImageUpload(
          mimeType: 'application/pdf',
          byteLength: 1024,
        ),
        throwsArgumentError,
      );
      expect(
        () => ConversationService.validateImageUpload(
          mimeType: 'image/webp',
          byteLength: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => ConversationService.validateImageUpload(
          mimeType: 'image/webp',
          byteLength: ConversationService.maxImageBytes + 1,
        ),
        throwsArgumentError,
      );
    });
  });
}
