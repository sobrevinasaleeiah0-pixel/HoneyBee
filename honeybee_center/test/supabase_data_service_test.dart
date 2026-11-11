import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/services/supabase_data_service.dart';

void main() {
  group('SupabaseDataService - Mapping and Invariant Tests', () {
    final mockProductsRows = [
      {
        'id': 'uuid-prod-lukot',
        'external_id': 'prod_lukot',
        'name': 'Stingless Bees (Lukot)',
        'category': 'Stingless Bees',
        'variety': 'Lukot',
        'description': 'Pure stingless bee honey',
        'is_active': true,
        'product_variants': [
          {
            'id': 'uuid-v-luk-1kg',
            'external_id': 'v_luk_1kg',
            'size': '1kg',
            'price': 1200,
            'reorder_level': 3,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-luk-350g',
            'external_id': 'v_luk_350g',
            'size': '350g',
            'price': 420,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-luk-400g',
            'external_id': 'v_luk_400g',
            'size': '400g',
            'price': 480,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-luk-500g',
            'external_id': 'v_luk_500g',
            'size': '500g',
            'price': 600,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-luk-650g',
            'external_id': 'v_luk_650g',
            'size': '650g',
            'price': 780,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
        ],
      },
      {
        'id': 'uuid-prod-mel',
        'external_id': 'prod_mellifera',
        'name': 'Sweet Honey (Mellifera)',
        'category': 'Sweet Honey',
        'variety': 'Mellifera',
        'description': '',
        'is_active': false,
        'product_variants': [
          {
            'id': 'uuid-v-mel-1kg',
            'external_id': 'v_mel_1kg',
            'size': '1kg',
            'price': 1010,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-mel-200g',
            'external_id': 'v_mel_200g',
            'size': '200g',
            'price': 210,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-mel-250g',
            'external_id': 'v_mel_250g',
            'size': '250g',
            'price': 260,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-mel-350g',
            'external_id': 'v_mel_350g',
            'size': '350g',
            'price': 360,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-mel-400g',
            'external_id': 'v_mel_400g',
            'size': '400g',
            'price': 410,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-mel-500g',
            'external_id': 'v_mel_500g',
            'size': '500g',
            'price': 510,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-mel-660g',
            'external_id': 'v_mel_660g',
            'size': '660g',
            'price': 660,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
        ],
      },
      {
        'id': 'uuid-prod-others',
        'external_id': 'prod_others',
        'name': 'Other Honey Products',
        'category': 'Others',
        'variety': '',
        'description': '',
        'is_active': true,
        'product_variants': [
          {
            'id': 'uuid-v-comb-650g',
            'external_id': 'v_comb_650g',
            'size': 'Honeycomb (650g)',
            'price': 845,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-pol-500g',
            'external_id': 'v_pollen_500g',
            'size': 'Honey With Pollen 500g',
            'price': 800,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-prop-100g',
            'external_id': 'v_propolis_100g',
            'size': 'Propolis (100g)',
            'price': 500,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-wax-1kg',
            'external_id': 'v_wax_1kg',
            'size': 'Bees Wax (kg)',
            'price': 650,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
        ],
      },
      {
        'id': 'uuid-prod-puk',
        'external_id': 'prod_pukyutan',
        'name': 'Pukyutan Honey',
        'category': 'Pukyutan Honey',
        'variety': 'Pukyutan',
        'description': '',
        'is_active': true,
        'product_variants': [
          {
            'id': 'uuid-v-puk-1kg',
            'external_id': 'v_puk_1kg',
            'size': '1kg',
            'price': 1110,
            'reorder_level': 5,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-puk-200g',
            'external_id': 'v_puk_200g',
            'size': '200g',
            'price': 230,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-puk-250g',
            'external_id': 'v_puk_250g',
            'size': '250g',
            'price': 285,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-puk-350g',
            'external_id': 'v_puk_350g',
            'size': '350g',
            'price': 395,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-puk-400g',
            'external_id': 'v_puk_400g',
            'size': '400g',
            'price': 450,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-puk-500g',
            'external_id': 'v_puk_500g',
            'size': '500g',
            'price': 560,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
          {
            'id': 'uuid-v-puk-650g',
            'external_id': 'v_puk_650g',
            'size': '650g',
            'price': 725,
            'reorder_level': 10,
            'product_qty': 0,
            'is_active': true,
          },
        ],
      },
    ];

    final mockInventoryRows = [
      {
        'products': {'external_id': 'prod_lukot'},
        'product_variants': {'external_id': 'v_luk_1kg'},
        'quantity': 80,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_lukot'},
        'product_variants': {'external_id': 'v_luk_350g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_lukot'},
        'product_variants': {'external_id': 'v_luk_400g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_lukot'},
        'product_variants': {'external_id': 'v_luk_500g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_lukot'},
        'product_variants': {'external_id': 'v_luk_650g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_mellifera'},
        'product_variants': {'external_id': 'v_mel_1kg'},
        'quantity': 10,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_mellifera'},
        'product_variants': {'external_id': 'v_mel_200g'},
        'quantity': 10,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_mellifera'},
        'product_variants': {'external_id': 'v_mel_250g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_mellifera'},
        'product_variants': {'external_id': 'v_mel_350g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_mellifera'},
        'product_variants': {'external_id': 'v_mel_400g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_mellifera'},
        'product_variants': {'external_id': 'v_mel_500g'},
        'quantity': 50,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_mellifera'},
        'product_variants': {'external_id': 'v_mel_660g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_others'},
        'product_variants': {'external_id': 'v_comb_650g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_others'},
        'product_variants': {'external_id': 'v_pollen_500g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_others'},
        'product_variants': {'external_id': 'v_propolis_100g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_others'},
        'product_variants': {'external_id': 'v_wax_1kg'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_pukyutan'},
        'product_variants': {'external_id': 'v_puk_1kg'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_pukyutan'},
        'product_variants': {'external_id': 'v_puk_200g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_pukyutan'},
        'product_variants': {'external_id': 'v_puk_250g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_pukyutan'},
        'product_variants': {'external_id': 'v_puk_350g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_pukyutan'},
        'product_variants': {'external_id': 'v_puk_400g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_pukyutan'},
        'product_variants': {'external_id': 'v_puk_500g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
      {
        'products': {'external_id': 'prod_pukyutan'},
        'product_variants': {'external_id': 'v_puk_650g'},
        'quantity': 0,
        'updated_at': '2026-10-12T00:00:00Z',
      },
    ];

    test('maps products and variants correctly into nested Map format', () {
      final mappedProducts = SupabaseDataService.mapSupabaseProducts(
        mockProductsRows,
      );

      // Verify product count
      expect(mappedProducts.length, equals(4));
      expect(mappedProducts.containsKey('prod_lukot'), isTrue);
      expect(mappedProducts.containsKey('prod_mellifera'), isTrue);
      expect(mappedProducts.containsKey('prod_others'), isTrue);
      expect(mappedProducts.containsKey('prod_pukyutan'), isTrue);
      expect(
        mappedProducts.values.where((p) => p['variety'] == 'Mellifera').length,
        equals(1),
      );

      // Verify variant count across products
      int totalVariants = 0;
      int totalStorefrontStock = 0;
      mappedProducts.forEach((key, p) {
        final variants = p['variants'] as Map<String, dynamic>;
        totalVariants += variants.length;
        variants.forEach((vKey, v) {
          totalStorefrontStock += (v['productQuantity'] as int);
        });
      });

      expect(totalVariants, equals(23));
      // Storefront stock must be exactly 0
      expect(totalStorefrontStock, equals(0));

      // Check specific variant details
      final lukot1kg = mappedProducts['prod_lukot']['variants']['v_luk_1kg'];
      expect(lukot1kg['size'], equals('1kg'));
      expect(lukot1kg['price'], equals(1200));
      expect(lukot1kg['reorderLevel'], equals(3));
      expect(lukot1kg['productQuantity'], equals(0));
      expect(lukot1kg['productQty'], equals(0));
      expect(lukot1kg['isActive'], isTrue);

      final mellifera = mappedProducts['prod_mellifera'];
      expect(mellifera['uuid'], equals('uuid-prod-mel'));
      expect(mellifera['isActive'], isFalse);
      final mellifera500g = mellifera['variants']['v_mel_500g'];
      expect(mellifera500g['uuid'], equals('uuid-v-mel-500g'));
      expect(mellifera500g['productQuantity'], equals(0));
    });

    test(
      'maps inventory correctly and maintains total warehouse stock of 150',
      () {
        final mappedInv = SupabaseDataService.mapSupabaseInventory(
          mockInventoryRows,
        );

        expect(mappedInv.containsKey('prod_lukot'), isTrue);
        expect(mappedInv['prod_lukot']['v_luk_1kg']['quantity'], equals(80));

        expect(mappedInv.containsKey('prod_mellifera'), isTrue);
        expect(
          mappedInv['prod_mellifera']['v_mel_1kg']['quantity'],
          equals(10),
        );
        expect(
          mappedInv['prod_mellifera']['v_mel_200g']['quantity'],
          equals(10),
        );
        expect(
          mappedInv['prod_mellifera']['v_mel_500g']['quantity'],
          equals(50),
        );
        // Calculate total warehouse stock
        int totalWarehouseStock = 0;
        mappedInv.forEach((pId, variants) {
          (variants as Map<String, dynamic>).forEach((vId, vData) {
            totalWarehouseStock += (vData['quantity'] as int);
          });
        });

        // Warehouse stock invariant: exactly 150 units
        expect(totalWarehouseStock, equals(150));
      },
    );

    test('preserves dual-pool stock separation invariant', () {
      final mappedProducts = SupabaseDataService.mapSupabaseProducts(
        mockProductsRows,
      );
      final mappedInv = SupabaseDataService.mapSupabaseInventory(
        mockInventoryRows,
      );

      int totalStorefront = 0;
      mappedProducts.forEach((_, p) {
        (p['variants'] as Map<String, dynamic>).forEach((_, v) {
          totalStorefront += (v['productQuantity'] as int);
        });
      });

      int totalWarehouse = 0;
      mappedInv.forEach((_, variants) {
        (variants as Map<String, dynamic>).forEach((_, vData) {
          totalWarehouse += (vData['quantity'] as int);
        });
      });

      expect(
        totalStorefront,
        equals(0),
        reason: 'Storefront product_qty must remain 0',
      );
      expect(
        totalWarehouse,
        equals(150),
        reason: 'Warehouse inventory must be exactly 150',
      );
      expect(totalStorefront != totalWarehouse, isTrue);
      final mellifera500g =
          mappedProducts['prod_mellifera']['variants']['v_mel_500g'];
      expect(mellifera500g['productQuantity'], equals(0));
      expect(mappedInv['prod_mellifera']['v_mel_500g']['quantity'], equals(50));
    });

    test('validates replenishment quantity and RPC result statuses', () {
      expect(
        () => SupabaseDataService.validateReplenishmentQuantity(1),
        returnsNormally,
      );
      expect(
        () => SupabaseDataService.validateReplenishmentQuantity(0),
        throwsArgumentError,
      );
      expect(
        () => SupabaseDataService.validateReplenishmentQuantity(-1),
        throwsArgumentError,
      );

      expect(
        SupabaseDataService.replenishmentFailureMessage('SUCCESS'),
        isNull,
      );
      expect(
        SupabaseDataService.replenishmentFailureMessage(
          'INSUFFICIENT_INVENTORY:10',
        ),
        'Not enough warehouse inventory. Available: 10 units.',
      );
      expect(
        SupabaseDataService.replenishmentFailureMessage('NO_VARIANT'),
        contains('variant no longer exists'),
      );
    });

    test('maps Supabase orders and order_items correctly', () {
      final mockOrdersRows = [
        {
          'id': 'd1111111-1111-1111-1111-111111111111',
          'order_reference': 'HB-20261013-ABCD',
          'customer_id': 'c1111111-1111-1111-1111-111111111111',
          'customer_name': 'Maria Santos',
          'customer_email': 'maria@example.com',
          'customer_phone': '09171234567',
          'customer_address': 'Davao City',
          'order_date': '2026-10-13',
          'order_status': 'Ready for Pickup',
          'payment_method': 'GCash',
          'payment_status': 'Confirmed',
          'payment_reference': 'GCASH-987654',
          'payment_proof_url': 'https://example.com/proof.jpg',
          'payment_amount': 780.00,
          'payment_verified_at': '2026-10-13T08:00:00Z',
          'payment_verified_by': 'a1111111-1111-1111-1111-111111111111',
          'payment_rejection_reason': null,
          'total_amount': 780.00,
          'product_qty_deducted': false,
          'ready_for_pickup_at': '2026-10-13T08:30:00Z',
          'pickup_reminder_sent': false,
          'pickup_reminder_sent_at': null,
          'picked_up_at': null,
          'picked_up_by': null,
          'created_at': '2026-10-13T07:45:00Z',
          'updated_at': '2026-10-13T08:30:00Z',
          'order_items': [
            {
              'id': 'item-1',
              'order_id': 'd1111111-1111-1111-1111-111111111111',
              'product_id': 'uuid-prod-lukot',
              'variant_id': 'uuid-v-luk-650g',
              'product_name': 'Stingless Bees (Lukot)',
              'bottle_size': '650g',
              'unit_price': 780.00,
              'quantity': 1,
              'subtotal': 780.00,
            },
          ],
        },
        {
          'id': 'd2222222-2222-2222-2222-222222222222',
          'order_reference': 'HB-20261012-WXYZ',
          'customer_id': 'c2222222-2222-2222-2222-222222222222',
          'customer_name': 'Juan Dela Cruz',
          'customer_email': 'juan@example.com',
          'customer_phone': '09187654321',
          'customer_address': 'Tagum City',
          'order_date': '2026-10-12',
          'order_status': 'Completed',
          'payment_method': 'Cash',
          'payment_status': 'Paid',
          'payment_reference': null,
          'payment_proof_url': null,
          'payment_amount': 1020.00,
          'payment_verified_at': '2026-10-12T10:00:00Z',
          'payment_verified_by': 'a1111111-1111-1111-1111-111111111111',
          'payment_rejection_reason': null,
          'total_amount': 1020.00,
          'product_qty_deducted': true,
          'ready_for_pickup_at': '2026-10-12T09:00:00Z',
          'pickup_reminder_sent': false,
          'pickup_reminder_sent_at': null,
          'picked_up_at': '2026-10-12T11:00:00Z',
          'picked_up_by': 'Honeybee Admin',
          'created_at': '2026-10-12T08:00:00Z',
          'updated_at': '2026-10-12T11:00:00Z',
          'order_items': [
            {
              'id': 'item-2',
              'order_id': 'd2222222-2222-2222-2222-222222222222',
              'product_id': 'uuid-prod-mel',
              'variant_id': 'uuid-v-mel-500g',
              'product_name': 'Sweet Honey (Mellifera)',
              'bottle_size': '500g',
              'unit_price': 510.00,
              'quantity': 2,
              'subtotal': 1020.00,
            },
          ],
        },
      ];

      final mappedOrders = SupabaseDataService.mapSupabaseOrders(
        mockOrdersRows,
      );

      expect(mappedOrders.length, equals(2));

      // First order checks
      final o1 = mappedOrders[0];
      expect(o1['id'], equals('d1111111-1111-1111-1111-111111111111'));
      expect(o1['orderReference'], equals('HB-20261013-ABCD'));
      expect(o1['customerName'], equals('Maria Santos'));
      expect(o1['orderStatus'], equals('Ready for Pickup'));
      expect(o1['paymentStatus'], equals('Confirmed'));
      expect(o1['totalAmount'], equals(780.0));
      expect(o1['inventoryDeducted'], isFalse);
      expect(o1['pickupStatus'], equals('Ready'));
      expect(o1['items'], isA<Map<String, dynamic>>());
      expect(o1['itemList'], isA<List<Map<String, dynamic>>>());
      expect((o1['itemList'] as List).length, equals(1));
      expect(
        o1['itemList'][0]['productName'],
        equals('Stingless Bees (Lukot)'),
      );
      expect(o1['itemList'][0]['bottleSize'], equals('650g'));
      expect(o1['itemList'][0]['quantity'], equals(1));
      expect(o1['itemList'][0]['price'], equals(780.0));

      // Second order checks
      final o2 = mappedOrders[1];
      expect(o2['id'], equals('d2222222-2222-2222-2222-222222222222'));
      expect(o2['orderReference'], equals('HB-20261012-WXYZ'));
      expect(o2['orderStatus'], equals('Completed'));
      expect(o2['paymentStatus'], equals('Paid'));
      expect(o2['inventoryDeducted'], isTrue);
      expect(o2['pickupStatus'], equals('Picked Up'));
      expect(o2['pickedUpBy'], equals('Honeybee Admin'));
      expect(o2['totalAmount'], equals(1020.0));
      expect(o2['itemList'][0]['quantity'], equals(2));
    });

    test(
      'enforces that only completed orders have inventoryDeducted = true',
      () {
        final mockOrdersRows = [
          {
            'id': 'ord-pending',
            'order_status': 'Pending',
            'payment_status': 'Pending',
            'product_qty_deducted': false,
            'total_amount': 500,
            'order_items': [],
          },
          {
            'id': 'ord-confirmed',
            'order_status': 'Confirmed',
            'payment_status': 'Confirmed',
            'product_qty_deducted': false,
            'total_amount': 500,
            'order_items': [],
          },
          {
            'id': 'ord-completed',
            'order_status': 'Completed',
            'payment_status': 'Paid',
            'product_qty_deducted': true,
            'total_amount': 500,
            'order_items': [],
          },
        ];

        final mapped = SupabaseDataService.mapSupabaseOrders(mockOrdersRows);
        expect(mapped[0]['inventoryDeducted'], isFalse);
        expect(mapped[1]['inventoryDeducted'], isFalse);
        expect(mapped[2]['inventoryDeducted'], isTrue);
      },
    );

    test('allows QR pickup only for paid, ready, unprocessed orders', () {
      const readyOrder = {
        'orderStatus': 'Ready for Pickup',
        'paymentStatus': 'Confirmed',
        'inventoryDeducted': false,
        'productQtyDeducted': false,
        'pickedUpAt': null,
      };

      expect(SupabaseDataService.pickupIneligibilityReason(readyOrder), isNull);
      expect(
        SupabaseDataService.pickupIneligibilityReason({
          ...readyOrder,
          'paymentStatus': 'Pending',
        }),
        equals('Payment Not Completed'),
      );
      expect(
        SupabaseDataService.pickupIneligibilityReason({
          ...readyOrder,
          'orderStatus': 'Preparing',
        }),
        equals('Order Not Ready for Pickup'),
      );
      expect(
        SupabaseDataService.pickupIneligibilityReason({
          ...readyOrder,
          'orderStatus': 'Cancelled',
        }),
        equals('Order Cancelled'),
      );
      expect(
        SupabaseDataService.pickupIneligibilityReason({
          ...readyOrder,
          'pickedUpAt': '2026-10-13T10:00:00Z',
        }),
        equals('Order Already Picked Up'),
      );
      expect(
        SupabaseDataService.pickupIneligibilityReason({
          ...readyOrder,
          'productQtyDeducted': true,
        }),
        equals('Order Already Processed'),
      );
    });

    test('identifies wallet payment orders independent of status case', () {
      expect(
        SupabaseDataService.isPaymentVerificationOrder({
          'paymentMethod': 'gCaSh',
          'paymentStatus': 'Pending',
        }),
        isTrue,
      );
      expect(
        SupabaseDataService.isPaymentVerificationOrder({
          'paymentMethod': 'Cash / Unspecified',
          'paymentStatus': 'Pending',
        }),
        isFalse,
      );
      expect(
        SupabaseDataService.isPaymentVerificationOrder({
          'paymentReferenceNumber': 'REF-123',
        }),
        isTrue,
      );
      expect(
        SupabaseDataService.isPaymentVerificationOrder({
          'paymentProofUrl': 'proof.png',
        }),
        isTrue,
      );
    });

    test('normalizes Supabase payment states for verification filters', () {
      expect(
        SupabaseDataService.paymentVerificationStatus({
          'paymentStatus': 'Pending',
        }),
        'Pending Verification',
      );
      expect(
        SupabaseDataService.paymentVerificationStatus({
          'paymentStatus': 'Paid',
        }),
        'Confirmed',
      );
      expect(
        SupabaseDataService.paymentVerificationStatus({
          'paymentStatus': 'Rejected',
        }),
        'Rejected',
      );
    });
  });
}
