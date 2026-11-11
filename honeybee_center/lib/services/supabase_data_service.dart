import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service dedicated to reading and mapping Product & Inventory data from Supabase.
/// Preserves dual-pool stock separation:
/// - Warehouse stock: public.inventory.quantity (bulk warehouse inventory)
/// - Storefront stock: public.product_variants.product_qty (storefront available stock)
class SupabaseDataService {
  static final SupabaseDataService _instance = SupabaseDataService._internal();
  factory SupabaseDataService() => _instance;
  SupabaseDataService._internal();

  SupabaseClient get _client => Supabase.instance.client;

  final BehaviorSubject<Map<String, dynamic>> _productsSubject =
      BehaviorSubject<Map<String, dynamic>>.seeded(<String, dynamic>{});
  final BehaviorSubject<Map<String, dynamic>> _inventorySubject =
      BehaviorSubject<Map<String, dynamic>>.seeded(<String, dynamic>{});
  final BehaviorSubject<List<Map<String, dynamic>>> _ordersSubject =
      BehaviorSubject<List<Map<String, dynamic>>>.seeded(
        <Map<String, dynamic>>[],
      );
  final BehaviorSubject<List<Map<String, dynamic>>> _customersSubject =
      BehaviorSubject<List<Map<String, dynamic>>>.seeded(
        <Map<String, dynamic>>[],
      );
  final BehaviorSubject<List<Map<String, dynamic>>> _inventoryMovementsSubject =
      BehaviorSubject<List<Map<String, dynamic>>>.seeded(
        <Map<String, dynamic>>[],
      );
  final BehaviorSubject<List<Map<String, dynamic>>> _productionBatchesSubject =
      BehaviorSubject<List<Map<String, dynamic>>>.seeded(
        <Map<String, dynamic>>[],
      );

  /// Stream of products matching the nested Map format expected by products_page and inventory_page
  Stream<Map<String, dynamic>> get productsStream => _productsSubject.stream;

  /// Stream of warehouse inventory matching the nested Map format: { productId: { variantId: { 'quantity': int } } }
  Stream<Map<String, dynamic>> get inventoryStream => _inventorySubject.stream;

  /// Stream of orders list
  Stream<List<Map<String, dynamic>>> get ordersStream => _ordersSubject.stream;

  Stream<List<Map<String, dynamic>>> get customersStream =>
      _customersSubject.stream;

  Stream<List<Map<String, dynamic>>> get inventoryMovementsStream =>
      _inventoryMovementsSubject.stream;

  /// Stream of production batches (includes nested production_batch_items)
  Stream<List<Map<String, dynamic>>> get productionBatchesStream =>
      _productionBatchesSubject.stream;

  /// Current cached production batches
  List<Map<String, dynamic>> get currentProductionBatches =>
      _productionBatchesSubject.value;

  /// Current cached products map
  Map<String, dynamic> get currentProducts => _productsSubject.value;

  /// Current cached inventory map
  Map<String, dynamic> get currentInventory => _inventorySubject.value;

  /// Current cached orders list
  List<Map<String, dynamic>> get currentOrders => _ordersSubject.value;

  /// Pure mapping function: converts Supabase product + variant query results
  /// into the exact nested Map expected by Honeybee Center UI widgets.
  static Map<String, dynamic> mapSupabaseProducts(List<dynamic> rows) {
    final Map<String, dynamic> productsMap = {};

    for (final row in rows) {
      if (row is! Map) continue;
      final p = Map<String, dynamic>.from(row);
      final extId = p['external_id']?.toString() ?? p['id']?.toString();
      if (extId == null || extId.isEmpty) continue;

      final Map<String, dynamic> variantsMap = {};
      final rawVariants = p['product_variants'];
      if (rawVariants is List) {
        for (final vRow in rawVariants) {
          if (vRow is! Map) continue;
          final v = Map<String, dynamic>.from(vRow);
          final vExtId = v['external_id']?.toString() ?? v['id']?.toString();
          if (vExtId == null || vExtId.isEmpty) continue;

          final storefrontQty = (v['product_qty'] as num?)?.toInt() ?? 0;
          variantsMap[vExtId] = <String, dynamic>{
            'id': vExtId,
            'uuid': v['id'],
            'size': v['size'] ?? '',
            'price': (v['price'] as num?)?.toInt() ?? 0,
            'reorderLevel': (v['reorder_level'] as num?)?.toInt() ?? 10,
            // Both fields mapped to ensure backward compatibility across all screens
            'productQuantity': storefrontQty,
            'productQty': storefrontQty,
            'isActive': v['is_active'] ?? true,
          };
        }
      }

      productsMap[extId] = <String, dynamic>{
        'id': extId,
        'uuid': p['id'],
        'name': p['name'] ?? '',
        'category': p['category'] ?? '',
        'variety': p['variety'] ?? '',
        'description': p['description'] ?? '',
        'isActive': p['is_active'] ?? true,
        'variants': variantsMap,
      };
    }

    return productsMap;
  }

  /// Pure mapping function: converts Supabase inventory query results
  /// into the exact nested Map expected by Honeybee Center UI widgets.
  static Map<String, dynamic> mapSupabaseInventory(List<dynamic> rows) {
    final Map<String, dynamic> invMap = {};

    for (final row in rows) {
      if (row is! Map) continue;
      final r = Map<String, dynamic>.from(row);

      // Support joined external IDs or direct variant/product keys
      final pExt = r['products'] is Map
          ? r['products']['external_id']?.toString()
          : r['product_external_id']?.toString();
      final vExt = r['product_variants'] is Map
          ? r['product_variants']['external_id']?.toString()
          : r['variant_external_id']?.toString();

      if (pExt == null || vExt == null) continue;

      invMap.putIfAbsent(pExt, () => <String, dynamic>{});
      invMap[pExt][vExt] = <String, dynamic>{
        'quantity': (r['quantity'] as num?)?.toInt() ?? 0,
        'lastUpdated': r['updated_at'],
        'id': r['id'],
      };
    }

    return invMap;
  }

  /// Fetches products and variants from Supabase and updates productsStream
  Future<Map<String, dynamic>> fetchProducts() async {
    try {
      final response = await _client
          .from('products')
          .select('''
            id,
            external_id,
            name,
            category,
            variety,
            description,
            is_active,
            created_at,
            updated_at,
            product_variants (
              id,
              external_id,
              size,
              price,
              reorder_level,
              product_qty,
              is_active
            )
          ''')
          .order('name');

      final mapped = mapSupabaseProducts(response as List);
      _productsSubject.add(mapped);
      return mapped;
    } catch (e) {
      debugPrint('[SupabaseDataService] Error fetching products: $e');
      rethrow;
    }
  }

  /// Pure mapping function: converts Supabase order query results
  /// into the exact Map representation expected by Honeybee Center UI widgets.
  static List<Map<String, dynamic>> mapSupabaseOrders(List<dynamic> rows) {
    final List<Map<String, dynamic>> orders = [];

    for (final row in rows) {
      if (row is! Map) continue;
      final o = Map<String, dynamic>.from(row);
      final id = o['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final Map<String, dynamic> itemsMap = {};
      final List<Map<String, dynamic>> itemsList = [];
      final rawItems = o['order_items'];
      if (rawItems is List) {
        for (int i = 0; i < rawItems.length; i++) {
          final itmRow = rawItems[i];
          if (itmRow is! Map) continue;
          final itm = Map<String, dynamic>.from(itmRow);
          final itmKey = itm['id']?.toString() ?? 'item_$i';
          final unitPrice = (itm['unit_price'] as num?)?.toDouble() ?? 0.0;
          final qty = (itm['quantity'] as num?)?.toInt() ?? 1;
          final subtotal =
              (itm['subtotal'] as num?)?.toDouble() ?? (unitPrice * qty);

          final itemData = <String, dynamic>{
            'id': itm['id']?.toString() ?? itmKey,
            'productId': itm['product_id']?.toString() ?? '',
            'variantId': itm['variant_id']?.toString() ?? '',
            'productName': itm['product_name'] ?? 'Honey',
            'product': itm['product_name'] ?? 'Honey',
            'bottleSize': itm['bottle_size'] ?? '',
            'size': itm['bottle_size'] ?? '',
            'unitPrice': unitPrice,
            'price': unitPrice,
            'quantity': qty,
            'subtotal': subtotal,
          };

          itemsMap[itmKey] = itemData;
          itemsList.add(itemData);
        }
      }

      final totalAmt = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
      final orderStatus = o['order_status']?.toString() ?? 'Pending';
      final paymentStatus = o['payment_status']?.toString() ?? 'Pending';
      final isDeducted = o['product_qty_deducted'] == true;
      final isReminderSent = o['pickup_reminder_sent'] == true;

      int? readyForPickupAtMillis;
      if (o['ready_for_pickup_at'] != null) {
        readyForPickupAtMillis = DateTime.tryParse(
          o['ready_for_pickup_at'].toString(),
        )?.millisecondsSinceEpoch;
      }

      int? reminderSentAtMillis;
      if (o['pickup_reminder_sent_at'] != null) {
        reminderSentAtMillis = DateTime.tryParse(
          o['pickup_reminder_sent_at'].toString(),
        )?.millisecondsSinceEpoch;
      }

      final orderDateStr =
          o['order_date']?.toString() ??
          (o['created_at'] != null
              ? o['created_at'].toString().split('T')[0]
              : '');

      final mapped = <String, dynamic>{
        'id': id,
        'orderId': id,
        'orderReference': o['order_reference']?.toString() ?? '',
        'customerId': o['customer_id']?.toString(),
        'customerName': o['customer_name'] ?? 'Customer',
        'customerEmail': o['customer_email'] ?? '',
        'customerPhone': o['customer_phone'] ?? '',
        'customerAddress': o['customer_address'] ?? '',
        'orderDate': orderDateStr,
        'orderStatus': orderStatus,
        'paymentMethod': o['payment_method'] ?? 'Cash / Unspecified',
        'paymentStatus': paymentStatus,
        'paymentReferenceNumber': o['payment_reference'],
        'paymentProofUrl': o['payment_proof_url'],
        'paymentProof': o['payment_proof_url'],
        'paymentAmount': (o['payment_amount'] as num?)?.toDouble(),
        'paymentSubmittedAt': o['created_at'],
        'paymentVerifiedAt': o['payment_verified_at'],
        'paymentRejectionReason': o['payment_rejection_reason'],
        'totalAmount': totalAmt,
        'total': totalAmt,
        'amount': totalAmt,
        'inventoryDeducted': isDeducted,
        'productQtyDeducted': isDeducted,
        'readyForPickupAt': readyForPickupAtMillis,
        'pickupReminderSent': isReminderSent,
        'pickupReminderSentAt': reminderSentAtMillis,
        'pickedUpAt': o['picked_up_at'],
        'pickedUpBy': o['picked_up_by'],
        'pickupStatus': o['picked_up_at'] != null
            ? 'Picked Up'
            : (orderStatus == 'Ready for Pickup' ? 'Ready' : orderStatus),
        'createdAt': o['created_at'],
        'updatedAt': o['updated_at'],
        'items': itemsMap,
        'itemList': itemsList,
      };

      orders.add(mapped);
    }

    return orders;
  }

  /// Returns the scanner state explaining why an order cannot be picked up.
  /// A pickup is allowed only after payment verification and readiness.
  static String? pickupIneligibilityReason(Map<String, dynamic> order) {
    final orderStatus = order['orderStatus']?.toString();
    if (orderStatus == 'Cancelled') return 'Order Cancelled';
    if (order['pickedUpAt'] != null) {
      return 'Order Already Picked Up';
    }
    if (orderStatus == 'Completed' ||
        order['inventoryDeducted'] == true ||
        order['productQtyDeducted'] == true) {
      return 'Order Already Processed';
    }

    final paymentStatus = order['paymentStatus']?.toString();
    if (paymentStatus != 'Confirmed' && paymentStatus != 'Paid') {
      return 'Payment Not Completed';
    }
    if (orderStatus != 'Ready for Pickup') {
      return 'Order Not Ready for Pickup';
    }
    return null;
  }

  static bool isPaymentVerificationOrder(Map<String, dynamic> order) {
    final method = order['paymentMethod']?.toString().trim().toLowerCase();
    return method == 'gcash' ||
        method == 'maya' ||
        (order['paymentReferenceNumber']?.toString().trim().isNotEmpty ??
            false) ||
        (order['paymentProofUrl']?.toString().trim().isNotEmpty ?? false);
  }

  static String paymentVerificationStatus(Map<String, dynamic> order) {
    final status = order['paymentStatus']?.toString().trim().toLowerCase();
    switch (status) {
      case 'confirmed':
      case 'paid':
        return 'Confirmed';
      case 'rejected':
        return 'Rejected';
      case 'pending':
      case 'pending verification':
      case null:
      case '':
        return 'Pending Verification';
      default:
        return order['paymentStatus'].toString();
    }
  }

  /// Fetches warehouse inventory from Supabase and updates inventoryStream
  Future<Map<String, dynamic>> fetchInventory() async {
    try {
      final response = await _client.from('inventory').select('''
            id,
            quantity,
            updated_at,
            products (external_id),
            product_variants (external_id)
          ''');

      final mapped = mapSupabaseInventory(response as List);
      _inventorySubject.add(mapped);
      return mapped;
    } catch (e) {
      debugPrint('[SupabaseDataService] Error fetching inventory: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    try {
      final response = await _client
          .from('customers')
          .select('id, auth_uid, name, email, phone, status, created_at')
          .order('created_at', ascending: false);
      final customers = (response as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      _customersSubject.add(customers);
      return customers;
    } catch (e) {
      debugPrint('[SupabaseDataService] Error fetching customers: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchInventoryMovements() async {
    try {
      final response = await _client
          .from('inventory_movements')
          .select(
            'id, movement_type, quantity_change, new_quantity, reference_id, created_at',
          )
          .order('created_at', ascending: false)
          .limit(50);
      final movements = (response as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
      _inventoryMovementsSubject.add(movements);
      return movements;
    } catch (e) {
      debugPrint(
        '[SupabaseDataService] Error fetching inventory movements: $e',
      );
      rethrow;
    }
  }

  Future<void> createCatalogProduct({
    required String name,
    String? variety,
    String? category,
    String? description,
  }) async {
    await _client.rpc(
      'create_catalog_product',
      params: {
        'p_name': name.trim(),
        'p_variety': _nullableTrimmed(variety),
        'p_category': _nullableTrimmed(category),
        'p_description': _nullableTrimmed(description),
      },
    );
    await refreshAll();
  }

  Future<void> updateCatalogProduct({
    required String productUuid,
    required String name,
    String? variety,
    String? description,
  }) async {
    await _client.rpc(
      'update_catalog_product',
      params: {
        'p_product_id': productUuid,
        'p_name': name.trim(),
        'p_variety': _nullableTrimmed(variety),
        'p_description': _nullableTrimmed(description),
      },
    );
    await refreshAll();
  }

  Future<void> setCatalogProductActive({
    required String productUuid,
    required bool isActive,
  }) async {
    await _client.rpc(
      'set_catalog_product_active',
      params: {'p_product_id': productUuid, 'p_is_active': isActive},
    );
    await refreshAll();
  }

  Future<void> createCatalogVariant({
    required String productUuid,
    required String size,
    required int price,
    required int reorderLevel,
  }) async {
    await _client.rpc(
      'create_catalog_variant',
      params: {
        'p_product_id': productUuid,
        'p_size': size.trim(),
        'p_price': price,
        'p_reorder_level': reorderLevel,
      },
    );
    await refreshAll();
  }

  Future<void> updateCatalogVariant({
    required String variantUuid,
    required int price,
    required int reorderLevel,
    required bool isActive,
  }) async {
    await _client.rpc(
      'update_catalog_variant',
      params: {
        'p_variant_id': variantUuid,
        'p_price': price,
        'p_reorder_level': reorderLevel,
        'p_is_active': isActive,
      },
    );
    await refreshAll();
  }

  Future<void> replenishProductQuantity({
    required String variantUuid,
    required int quantity,
    required String adminUid,
  }) async {
    validateReplenishmentQuantity(quantity);

    final result = await _client.rpc(
      'replenish_product_qty',
      params: {
        'p_variant_id': variantUuid,
        'p_qty': quantity,
        'p_admin_id': adminUid,
      },
    );
    final status = result.toString();
    final failureMessage = replenishmentFailureMessage(status);
    if (failureMessage != null) {
      throw StateError(failureMessage);
    }

    await refreshAll();
  }

  static void validateReplenishmentQuantity(int quantity) {
    if (quantity <= 0) {
      throw ArgumentError.value(quantity, 'quantity', 'Must be positive.');
    }
  }

  static String? replenishmentFailureMessage(String status) {
    if (status == 'SUCCESS') return null;
    if (status.startsWith('INSUFFICIENT_INVENTORY:')) {
      final available = status.substring('INSUFFICIENT_INVENTORY:'.length);
      return 'Not enough warehouse inventory. Available: $available units.';
    }
    if (status == 'INVALID_QTY') return 'Quantity must be greater than zero.';
    if (status == 'NO_VARIANT') {
      return 'The selected product variant no longer exists.';
    }
    if (status == 'NO_INVENTORY_NODE') {
      return 'No warehouse inventory record exists for this variant.';
    }
    return 'Stock transfer failed: $status';
  }

  String? _nullableTrimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// Fetches orders with order_items from Supabase and updates ordersStream
  Future<List<Map<String, dynamic>>> fetchOrders() async {
    try {
      final response = await _client
          .from('orders')
          .select('''
            id,
            order_reference,
            customer_id,
            customer_name,
            customer_email,
            customer_phone,
            customer_address,
            order_date,
            order_status,
            payment_method,
            payment_status,
            payment_reference,
            payment_proof_url,
            payment_amount,
            payment_verified_at,
            payment_verified_by,
            payment_rejection_reason,
            total_amount,
            product_qty_deducted,
            ready_for_pickup_at,
            pickup_reminder_sent,
            pickup_reminder_sent_at,
            picked_up_at,
            picked_up_by,
            created_at,
            updated_at,
            order_items (
              id,
              order_id,
              product_id,
              variant_id,
              product_name,
              bottle_size,
              unit_price,
              quantity,
              subtotal
            )
          ''')
          .order('created_at', ascending: false);

      final mapped = mapSupabaseOrders(response as List);
      _ordersSubject.add(mapped);
      return mapped;
    } catch (e) {
      debugPrint('[SupabaseDataService] Error fetching orders: $e');
      rethrow;
    }
  }

  /// Looks up an order by its exact customer-facing reference for the QR scanner
  Future<Map<String, dynamic>?> findOrderByReference(String reference) async {
    final ref = reference.trim().toUpperCase();
    if (ref.isEmpty) return null;
    try {
      final response = await _client
          .from('orders')
          .select('''
            id,
            order_reference,
            customer_id,
            customer_name,
            customer_email,
            customer_phone,
            customer_address,
            order_date,
            order_status,
            payment_method,
            payment_status,
            payment_reference,
            payment_proof_url,
            payment_amount,
            payment_verified_at,
            payment_verified_by,
            payment_rejection_reason,
            total_amount,
            product_qty_deducted,
            ready_for_pickup_at,
            pickup_reminder_sent,
            pickup_reminder_sent_at,
            picked_up_at,
            picked_up_by,
            created_at,
            updated_at,
            order_items (
              id,
              order_id,
              product_id,
              variant_id,
              product_name,
              bottle_size,
              unit_price,
              quantity,
              subtotal
            )
          ''')
          .eq('order_reference', ref)
          .limit(1);
      if (response.isNotEmpty) {
        final mappedList = mapSupabaseOrders(response);
        if (mappedList.isNotEmpty) {
          return mappedList.first;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[SupabaseDataService] Error looking up order: $e');
      rethrow;
    }
  }

  /// Updates order status in Supabase
  Future<bool> updateOrderStatus(String orderId, String status) async {
    try {
      final updates = <String, dynamic>{
        'order_status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (status == 'Ready for Pickup') {
        updates['ready_for_pickup_at'] = DateTime.now()
            .toUtc()
            .toIso8601String();
      }
      await _client.from('orders').update(updates).eq('id', orderId);
      await fetchOrders().catchError((_) => <Map<String, dynamic>>[]);
      return true;
    } catch (e) {
      debugPrint('[SupabaseDataService] Error updating order status: $e');
      rethrow;
    }
  }

  /// Updates payment verification status in Supabase
  Future<bool> updatePaymentStatus(
    String orderId,
    String status, {
    String? rejectionReason,
  }) async {
    try {
      final updates = <String, dynamic>{
        'payment_status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (status == 'Confirmed' || status == 'Paid') {
        updates['payment_verified_at'] = DateTime.now()
            .toUtc()
            .toIso8601String();
        final user = _client.auth.currentUser;
        if (user != null) {
          updates['payment_verified_by'] = user.id;
        }
      } else if (status == 'Rejected') {
        updates['payment_rejection_reason'] =
            rejectionReason ?? 'Invalid payment proof';
      }
      await _client.from('orders').update(updates).eq('id', orderId);
      await fetchOrders().catchError((_) => <Map<String, dynamic>>[]);
      return true;
    } catch (e) {
      debugPrint('[SupabaseDataService] Error updating payment status: $e');
      rethrow;
    }
  }

  /// Completes an order atomically via complete_order RPC function.
  /// Requires Co-Admin role and valid authenticated session.
  /// Deducts storefront product_qty, verifies payment, and ensures idempotency.
  Future<bool> completeOrder(String orderId) async {
    try {
      await _client.rpc('complete_order', params: {'p_order_id': orderId});
      await Future.wait([
        fetchOrders().catchError((_) => <Map<String, dynamic>>[]),
        fetchProducts().catchError((_) => <String, dynamic>{}),
      ]);
      return true;
    } catch (e) {
      debugPrint('[SupabaseDataService] completeOrder RPC error: $e');
      rethrow;
    }
  }

  /// Confirms customer order pickup in the QR scanner workflow.
  /// The RPC validates pickup and atomically performs stock deduction and audit.
  Future<bool> confirmPickup({
    required String orderId,
    required String orderReference,
  }) async {
    try {
      await _client.rpc(
        'confirm_order_pickup',
        params: {
          'p_order_id': orderId,
          'p_order_reference': orderReference.trim().toUpperCase(),
        },
      );

      try {
        await Future.wait([fetchOrders(), fetchProducts()]);
      } catch (e) {
        debugPrint(
          '[SupabaseDataService] Pickup succeeded but refresh failed: $e',
        );
      }
      return true;
    } catch (e) {
      debugPrint('[SupabaseDataService] confirmPickup error: $e');
      rethrow;
    }
  }

  /// Refreshes products, inventory, and orders concurrently
  Future<void> refreshAll() async {
    await Future.wait([
      fetchProducts(),
      fetchInventory(),
      fetchOrders(),
      fetchCustomers(),
      fetchInventoryMovements(),
      fetchProductionBatches(),
    ]);
  }

  /// Total warehouse stock bottles calculated from the current inventory map
  int get totalWarehouseStock {
    int total = 0;
    _inventorySubject.value.forEach((_, pVars) {
      if (pVars is Map) {
        pVars.forEach((_, vData) {
          if (vData is Map) {
            total += (vData['quantity'] as num?)?.toInt() ?? 0;
          }
        });
      }
    });
    return total;
  }

  /// Total storefront stock bottles calculated from the current products map
  int get totalStorefrontStock {
    int total = 0;
    _productsSubject.value.forEach((_, pData) {
      if (pData is Map) {
        final variants = pData['variants'];
        if (variants is Map) {
          variants.forEach((_, vData) {
            if (vData is Map) {
              total += (vData['productQuantity'] as num?)?.toInt() ?? 0;
            }
          });
        }
      }
    });
    return total;
  }

  /// Adjusts warehouse inventory via the secured adjust_inventory RPC function.
  /// Requires Co-Admin role and valid authenticated session.
  Future<bool> adjustInventory({
    required String variantUuid,
    required int change,
    required String reason,
    String? notes,
  }) async {
    try {
      final refId = 'manual_${DateTime.now().millisecondsSinceEpoch}';
      await _client.rpc(
        'adjust_inventory',
        params: {
          'p_variant_id': variantUuid,
          'p_change': change,
          'p_type': 'manual_adjustment',
          'p_reference_id': refId,
          'p_reason': reason,
          if (notes != null && notes.isNotEmpty) 'p_notes': notes,
        },
      );
      await refreshAll();
      return true;
    } catch (e) {
      debugPrint('[SupabaseDataService] adjustInventory RPC error: $e');
      rethrow;
    }
  }

  /// Dispose subjects on shutdown
  void dispose() {
    _productsSubject.close();
    _inventorySubject.close();
    _ordersSubject.close();
    _productionBatchesSubject.close();
  }

  // ── Inventory movements enriched (for history dialog) ─────────────────────

  /// Fetches inventory movements for a specific variant identified by its
  /// Firebase external_id string (e.g. 'v_mel_200g').
  /// Returns movements with product and variant external IDs for display.
  Future<List<Map<String, dynamic>>> fetchMovementsForVariantExternalId(
      String variantExternalId) async {
    try {
      final response = await _client
          .from('inventory_movements')
          .select(
            'id, movement_type, quantity_change, prev_quantity, new_quantity, '
            'reason, notes, created_at, '
            'product_variants!inner(external_id)',
          )
          .eq('product_variants.external_id', variantExternalId)
          .order('created_at', ascending: false);
      return (response as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (e) {
      debugPrint(
        '[SupabaseDataService] fetchMovementsForVariantExternalId error: $e',
      );
      rethrow;
    }
  }

  /// Fetches recent manual adjustments (movement_type = 'manual_adjustment')
  /// for the Stock Corrections tab recent history list.
  Future<List<Map<String, dynamic>>> fetchRecentManualAdjustments(
      {int limit = 15}) async {
    try {
      final response = await _client
          .from('inventory_movements')
          .select(
            'id, movement_type, quantity_change, prev_quantity, new_quantity, '
            'reason, notes, created_at, '
            'product_variants(external_id, size), '
            'products(external_id, name, variety)',
          )
          .eq('movement_type', 'manual_adjustment')
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (e) {
      debugPrint(
        '[SupabaseDataService] fetchRecentManualAdjustments error: $e',
      );
      rethrow;
    }
  }

  // ── Suppliers ─────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSuppliers() async {
    try {
      final response = await _client
          .from('suppliers')
          .select(
            'id, supplier_name, contact_person, contact_number, address, '
            'supplies, last_supply_date, notes, status, created_at, updated_at',
          )
          .order('supplier_name');
      return (response as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (e) {
      debugPrint('[SupabaseDataService] fetchSuppliers error: $e');
      rethrow;
    }
  }

  Future<void> createSupplier(Map<String, dynamic> data) async {
    await _client.from('suppliers').insert({
      'supplier_name': (data['supplierName'] ?? '').toString().trim(),
      'contact_person': data['contactPerson']?.toString(),
      'contact_number': data['contactNumber']?.toString(),
      'address': data['address']?.toString(),
      'supplies': data['supplies']?.toString(),
      'last_supply_date': data['lastSupplyDate']?.toString(),
      'notes': data['notes']?.toString(),
      'status': data['status']?.toString() ?? 'Active',
    });
  }

  Future<void> updateSupplier(
      String supplierId, Map<String, dynamic> data) async {
    await _client.from('suppliers').update({
      'supplier_name': (data['supplierName'] ?? '').toString().trim(),
      'contact_person': data['contactPerson']?.toString(),
      'contact_number': data['contactNumber']?.toString(),
      'address': data['address']?.toString(),
      'supplies': data['supplies']?.toString(),
      'last_supply_date': data['lastSupplyDate']?.toString(),
      'notes': data['notes']?.toString(),
      'status': data['status']?.toString() ?? 'Active',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', supplierId);
  }

  Future<void> deleteSupplier(String supplierId) async {
    await _client.from('suppliers').delete().eq('id', supplierId);
  }

  // ── Feedback ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchFeedback() async {
    try {
      final response = await _client
          .from('feedback')
          .select(
            'id, customer_name, customer_email, rating, message, '
            'order_id, product_name, admin_reply, replied_at, '
            'is_read, is_archived, created_at',
          )
          .order('created_at', ascending: false);
      return (response as List)
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (e) {
      debugPrint('[SupabaseDataService] fetchFeedback error: $e');
      rethrow;
    }
  }

  Future<void> markFeedbackRead(String feedbackId) async {
    await _client
        .from('feedback')
        .update({'is_read': true})
        .eq('id', feedbackId);
  }

  Future<void> markAllFeedbackRead() async {
    await _client
        .from('feedback')
        .update({'is_read': true})
        .eq('is_read', false)
        .eq('is_archived', false);
  }

  Future<void> archiveFeedback(String feedbackId,
      {required bool archive}) async {
    await _client
        .from('feedback')
        .update({'is_archived': archive})
        .eq('id', feedbackId);
  }

  Future<void> replyToFeedback(String feedbackId, String reply) async {
    await _client.from('feedback').update({
      'admin_reply': reply.trim(),
      'replied_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', feedbackId);
  }

  // ── Production ──────────────────────────────────────────────────────────────

  /// Fetches production batches from Supabase with nested batch_items.
  /// Preserves display fields (product_name, bottle_size, etc.) and
  /// maps snake_case → camelCase for existing UI widgets.
  Future<List<Map<String, dynamic>>> fetchProductionBatches({
    bool includeArchived = false,
  }) async {
    try {
      final selectColumns = '''
        id, external_id, product_id, variant_id, batch_name,
        is_bundle, status, qty_target, qty_completed,
        inventory_updated, inventory_added_qty,
        order_id, customer_name, items_summary, is_archived,
        created_by, completed_at, created_at, updated_at,
        bottle_size, product_name, production_date,
        start_date, target_completion_date,
        production_batch_items(
          id, product_id, variant_id, product_name,
          bottle_size, qty_target, qty_completed, status
        )
      ''';

      // .eq() must come before .order() in the Supabase query chain.
      final response = includeArchived
          ? await _client
              .from('production_batches')
              .select(selectColumns)
              .order('created_at', ascending: false)
          : await _client
              .from('production_batches')
              .select(selectColumns)
              .eq('is_archived', false)
              .order('created_at', ascending: false);

      final batches = (response as List)
          .whereType<Map>()
          .map((r) => _mapProductionBatch(Map<String, dynamic>.from(r)))
          .toList();
      _productionBatchesSubject.add(batches);
      return batches;
    } catch (e) {
      debugPrint('[SupabaseDataService] fetchProductionBatches error: $e');
      rethrow;
    }
  }

  /// Maps a Supabase production_batches row (snake_case) → camelCase for UI.
  static Map<String, dynamic> _mapProductionBatch(Map<String, dynamic> r) {
    return {
      'id':                     r['id']?.toString() ?? '',
      'externalId':             r['external_id']?.toString(),
      'productId':              r['product_id']?.toString(),
      'variantId':              r['variant_id']?.toString(),
      'productName':            r['product_name'] ?? '',
      'bottleSize':             r['bottle_size'] ?? '',
      'batchName':              r['batch_name'] ?? '',
      'isBundle':               r['is_bundle'] == true,
      'status':                 r['status'] ?? 'Planned',
      'quantityTarget':         (r['qty_target'] as num?)?.toInt() ?? 0,
      'quantityProduced':       (r['qty_target'] as num?)?.toInt() ?? 0,
      'completedQuantity':      (r['qty_completed'] as num?)?.toInt() ?? 0,
      'inventoryUpdated':       r['inventory_updated'] == true,
      'inventoryAddedQuantity': (r['inventory_added_qty'] as num?)?.toInt(),
      'orderId':                r['order_id']?.toString(),
      'customerName':           r['customer_name'] ?? '',
      'itemsSummary':           r['items_summary'] ?? '',
      'isArchived':             r['is_archived'] == true,
      'createdBy':              r['created_by']?.toString(),
      'completedAt':            r['completed_at']?.toString(),
      'targetCompletionDate':   r['target_completion_date'] ?? '',
      'productionDate':         r['production_date'] ?? '',
      'startDate':              r['start_date'] ?? '',
      'createdAt':              r['created_at']?.toString(),
      'updatedAt':              r['updated_at']?.toString(),
      // Nested items for bundle display — mapped to the same shape Firebase used.
      'items': _mapBatchItems(r['production_batch_items']),
    };
  }

  /// Maps production_batch_items List → Map keyed by item UUID (matches
  /// Firebase structure where items were keyed by push key).
  static Map<String, dynamic> _mapBatchItems(dynamic rawItems) {
    if (rawItems is! List) return {};
    final map = <String, dynamic>{};
    for (final item in rawItems.whereType<Map>()) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      map[id] = {
        'id':               id,
        'productId':        item['product_id']?.toString(),
        'variantId':        item['variant_id']?.toString(),
        'productName':      item['product_name'] ?? '',
        'bottleSize':       item['bottle_size'] ?? '',
        'targetQuantity':   (item['qty_target'] as num?)?.toInt() ?? 0,
        'quantityProduced': (item['qty_target'] as num?)?.toInt() ?? 0,
        'completedQuantity':(item['qty_completed'] as num?)?.toInt() ?? 0,
        'status':           item['status'] ?? 'Pending',
      };
    }
    return map;
  }

  // ── Production RPC wrappers ────────────────────────────────────────────────

  /// Creates a standard (non-bundle) production batch.
  /// Delegates to the `create_production_batch` Supabase RPC.
  Future<String> createProductionBatch({
    required String productExternalId,
    required String variantExternalId,
    required int qtyTarget,
    String? startDate,
    String? targetCompletionDate,
    String? batchName,
  }) async {
    final result = await _client.rpc('create_production_batch', params: {
      'p_product_external_id':     productExternalId,
      'p_variant_external_id':     variantExternalId,
      'p_qty_target':              qtyTarget,
      'p_start_date':              startDate,
      'p_target_completion_date':  targetCompletionDate,
      'p_batch_name':              batchName,
    });
    await fetchProductionBatches();
    return result.toString();
  }

  /// Creates a bulk (bundle) production batch + all child items atomically.
  /// Delegates to the `create_bulk_production_batch` Supabase RPC.
  Future<String> createBulkProductionBatch({
    required String orderId,
    required String customerName,
    required String bundleName,
    required int qtyTarget,
    required String initialStatus,
    String? itemsSummary,
    String? startDate,
    String? targetCompletionDate,
    required List<Map<String, dynamic>> items,
  }) async {
    final result = await _client.rpc('create_bulk_production_batch', params: {
      'p_order_id':               orderId,
      'p_customer_name':          customerName,
      'p_bundle_name':            bundleName,
      'p_qty_target':             qtyTarget,
      'p_initial_status':         initialStatus,
      'p_items_summary':          itemsSummary,
      'p_start_date':             startDate,
      'p_target_completion_date': targetCompletionDate,
      'p_items':                   items,
    });
    await fetchProductionBatches();
    return result.toString();
  }

  /// Updates a production batch's status and/or quantities.
  /// Blocks 'Completed' target — use completeProductionBatch() for that.
  Future<void> updateProductionBatchStatus({
    required String batchId,
    required String newStatus,
    int? qtyCompleted,
    int? qtyTarget,
  }) async {
    await _client.rpc('update_production_batch_status', params: {
      'p_batch_id':      batchId,
      'p_new_status':    newStatus,
      'p_qty_completed': qtyCompleted,
      'p_qty_target':    qtyTarget,
    });
    await fetchProductionBatches();
  }

  /// Completes a production batch — the ONLY path that adds to inventory.
  /// Delegates to the existing `complete_production` Supabase RPC.
  /// Returns false if already completed (idempotent — inventory untouched).
  Future<bool> completeProductionBatch(String batchId) async {
    final result = await _client.rpc(
      'complete_production',
      params: {'p_batch_id': batchId},
    );
    await fetchProductionBatches();
    return result == true;
  }

  /// Archives a production batch (soft delete).
  /// Does not delete rows or touch inventory.
  Future<void> archiveProductionBatch(String batchId) async {
    await _client.rpc('archive_production_batch', params: {
      'p_batch_id': batchId,
    });
    await fetchProductionBatches();
  }
}
