import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── Result type for addProductQuantity() ───────────────────────────────
class AddResult {
  final bool ok;
  final String? errorMessage;

  const AddResult._({required this.ok, this.errorMessage});

  static const AddResult success = AddResult._(ok: true);
  static const AddResult invalidQty = AddResult._(
    ok: false,
    errorMessage: 'Quantity must be greater than zero.',
  );
  static const AddResult noInventoryNode = AddResult._(
    ok: false,
    errorMessage: 'No inventory record found for this variant.',
  );
  static const AddResult transactionFailed = AddResult._(
    ok: false,
    errorMessage: 'Transaction failed. Please try again.',
  );

  static AddResult insufficientInventory(int available) => AddResult._(
    ok: false,
    errorMessage:
        'Not enough inventory available for adding stock. '
        'Available: $available unit${available == 1 ? '' : 's'}.',
  );
}

class DatabaseService {
  DatabaseReference get _db => FirebaseDatabase.instance.ref();
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get _currentUserId => _auth.currentUser?.uid;

  Stream<DatabaseEvent> _watch(String path) {
    try {
      if (Firebase.apps.isEmpty) {
        throw StateError(
          'Firebase is not initialized; "$path" is unavailable.',
        );
      }

      return _db
          .child(path)
          .onValue
          .transform(
            StreamTransformer<DatabaseEvent, DatabaseEvent>.fromHandlers(
              handleError: (error, stackTrace, sink) {
                debugPrint(
                  '[DatabaseService] Firebase stream "$path" failed: $error',
                );
                sink.addError(error, stackTrace);
              },
            ),
          );
    } catch (error, stackTrace) {
      debugPrint(
        '[DatabaseService] Firebase stream "$path" unavailable: $error',
      );
      return Stream<DatabaseEvent>.error(error, stackTrace);
    }
  }

  // --- PRODUCTS ---
  Stream<DatabaseEvent> getProductsStream() => _watch('products');

  Future<void> addProduct(Map<String, dynamic> productData) async {
    final ref = _db.child('products').push();
    await ref.set({
      ...productData,
      'id': ref.key,
      'isActive': true,
      'createdDate': ServerValue.timestamp,
      'updatedDate': ServerValue.timestamp,
    });
  }

  Future<void> updateProduct(
    String productId,
    Map<String, dynamic> productData,
  ) async {
    await _db.child('products').child(productId).update({
      ...productData,
      'updatedDate': ServerValue.timestamp,
    });
  }

  Future<void> archiveProduct(String productId, bool archive) async {
    await _db.child('products').child(productId).update({
      'isActive': !archive,
      'updatedDate': ServerValue.timestamp,
    });
  }

  // --- INVENTORY ---
  Stream<DatabaseEvent> getInventoryStream() => _watch('inventory');

  Future<void> initializeInventoryStock() async {
    final prodSnap = await _db.child('products').get();
    if (!prodSnap.exists || prodSnap.value == null) return;

    final products = Map<String, dynamic>.from(prodSnap.value as Map);
    final invSnap = await _db.child('inventory').get();
    final existing = invSnap.exists && invSnap.value is Map
        ? Map<String, dynamic>.from(invSnap.value as Map)
        : <String, dynamic>{};

    // Build ONLY the map of missing variant entries so we never overwrite
    // existing quantities — safe for concurrent admin sessions.
    final Map<String, dynamic> missing = {};
    products.forEach((pKey, pVal) {
      final pMap = Map<String, dynamic>.from(pVal as Map);
      final vars = pMap['variants'] as Map? ?? {};
      vars.forEach((vKey, _) {
        final existingProduct = existing[pKey];
        final alreadyExists =
            existingProduct is Map && existingProduct.containsKey(vKey);
        if (!alreadyExists) {
          missing['$pKey/$vKey'] = {
            'quantity': 0,
            'lastUpdated': ServerValue.timestamp,
          };
        }
      });
    });

    if (missing.isNotEmpty) {
      // update() writes only the listed paths — never touches existing entries.
      await _db.child('inventory').update(missing);
    }
  }

  /// Updates inventory and records movement.
  /// Uses a transaction-like approach to ensure consistency.
  Future<bool> updateInventory({
    required String productId,
    required String variantId,
    required int change,
    required String movementType,
    required String referenceId,
  }) async {
    if (productId.isEmpty ||
        variantId.isEmpty ||
        productId == 'null' ||
        variantId == 'null') {
      print(
        '[ERROR] updateInventory called with invalid productId/variantId: ($productId / $variantId)',
      );
      return false;
    }

    print(
      '[DEBUG] updateInventory called: path=inventory/$productId/$variantId, change=$change, refId=$referenceId',
    );
    final invRef = _db.child('inventory').child(productId).child(variantId);

    // Use runTransaction to prevent race conditions
    final TransactionResult result = await invRef.runTransaction((
      Object? value,
    ) {
      if (value == null) {
        // Initial state if node doesn't exist
        return Transaction.success({
          'quantity': change < 0 ? 0 : change,
          'lastUpdated': ServerValue.timestamp,
        });
      }

      Map<String, dynamic> data = Map<String, dynamic>.from(value as Map);
      int currentQty = data['quantity'] ?? 0;
      int newQty = currentQty + change;

      if (newQty < 0) newQty = 0; // Prevent negative stock

      data['quantity'] = newQty;
      data['lastUpdated'] = ServerValue.timestamp;

      return Transaction.success(data);
    });

    if (result.committed) {
      final Map<String, dynamic> snapshot = Map<String, dynamic>.from(
        result.snapshot.value as Map,
      );
      final int newQty = snapshot['quantity'];
      final int prevQty = newQty - change;
      print(
        '[DEBUG] updateInventory committed: path=inventory/$productId/$variantId, prevQty=$prevQty, newQty=$newQty',
      );

      await _createInventoryMovement(
        productId: productId,
        variantId: variantId,
        change: change,
        prevQty: prevQty,
        newQty: newQty,
        type: movementType,
        refId: referenceId,
      );

      await _checkLowStock(productId, variantId, newQty);
      return true;
    } else {
      print(
        '[DEBUG] updateInventory failed/not committed for path=inventory/$productId/$variantId',
      );
      return false;
    }
  }

  Future<void> _createInventoryMovement({
    required String productId,
    required String variantId,
    required int change,
    required int prevQty,
    required int newQty,
    required String type,
    required String refId,
    String? reason, // used by manual_adjustment only
    String? notes, // used by manual_adjustment only
  }) async {
    final ref = _db.child('inventory_movements').push();
    final data = <String, dynamic>{
      'id': ref.key,
      'productId': productId,
      'variantId': variantId,
      'type': type,
      'quantityChange': change,
      'previousQuantity': prevQty,
      'newQuantity': newQty,
      'referenceId': refId,
      'timestamp': ServerValue.timestamp,
      'adminId': _currentUserId,
    };
    if (reason != null) data['reason'] = reason;
    if (notes != null && notes.isNotEmpty) data['notes'] = notes;
    await ref.set(data);
  }

  Future<void> _checkLowStock(
    String productId,
    String variantId,
    int currentQty,
  ) async {
    final productSnap = await _db.child('products').child(productId).get();
    if (!productSnap.exists) return;

    final productData = Map<String, dynamic>.from(productSnap.value as Map);
    final variants = productData['variants'] as Map?;
    if (variants == null || !variants.containsKey(variantId)) return;

    final variantData = Map<String, dynamic>.from(variants[variantId]);
    final int reorderLevel = variantData['reorderLevel'] ?? 10;
    final String productName = productData['name'] ?? 'Unknown Product';
    final String size = variantData['size'] ?? '';

    if (currentQty <= reorderLevel) {
      String msg = currentQty == 0
          ? '$productName ($size) is OUT OF STOCK!'
          : '$productName ($size) is low in stock ($currentQty remaining).';

      await createNotification(
        type: currentQty == 0 ? 'OUT_OF_STOCK' : 'LOW_STOCK',
        message: msg,
        relatedId: productId,
      );
    }
  }

  // --- PRODUCTION ---
  Stream<DatabaseEvent> getProductionBatchesStream() =>
      _watch('production_batches');

  Future<void> createProductionBatch(Map<String, dynamic> batchData) async {
    final ref = _db.child('production_batches').push();
    await ref.set({
      ...batchData,
      'id': ref.key,
      'status': 'Planned',
      'inventoryUpdated': false,
      'isArchived': false,
      'createdTimestamp': ServerValue.timestamp,
      'createdBy': _currentUserId,
    });
  }

  Future<bool> completeProduction(String batchId) async {
    print('[DEBUG] completeProduction called for batchId: $batchId');
    final batchRef = _db.child('production_batches').child(batchId);

    Map<String, dynamic>? snapData;

    // Atomic transaction to claim completion and lock inventoryUpdated flag
    final TransactionResult result = await batchRef.runTransaction((
      Object? value,
    ) {
      if (value == null) return Transaction.abort();

      final data = Map<String, dynamic>.from(value as Map);

      // If archived or ALREADY inventoryUpdated, abort transaction immediately
      if (data['isArchived'] == true || data['inventoryUpdated'] == true) {
        return Transaction.abort();
      }

      data['inventoryUpdated'] = true;
      data['status'] = 'Completed';
      data['completedAt'] = ServerValue.timestamp;
      snapData = data;
      return Transaction.success(data);
    });

    if (!result.committed || snapData == null) {
      print(
        '[DEBUG] completeProduction: batch $batchId already processed or transaction aborted.',
      );
      return true;
    }

    final bool isBundle = snapData!['isBundle'] == true;

    if (!isBundle) {
      final int completedQty =
          int.tryParse(snapData!['completedQuantity']?.toString() ?? '0') ?? 0;
      final String? productId = snapData!['productId'];
      final String? variantId = snapData!['variantId'];

      if (productId != null &&
          variantId != null &&
          productId != 'null' &&
          variantId != 'null' &&
          completedQty > 0) {
        bool success = await updateInventory(
          productId: productId,
          variantId: variantId,
          change: completedQty,
          movementType: 'production',
          referenceId: batchId,
        );

        if (success) {
          await batchRef.update({'inventoryAddedQuantity': completedQty});
          await createNotification(
            type: 'PRODUCTION_COMPLETED',
            message:
                'Production batch #$batchId completed (+ $completedQty units).',
            relatedId: batchId,
          );
          return true;
        }
      }
    } else {
      // BUNDLE BATCH
      final itemsMap = Map<String, dynamic>.from(snapData!['items'] ?? {});
      int totalCompleted = 0;
      for (var entry in itemsMap.entries) {
        final itm = Map<String, dynamic>.from(entry.value);
        final String? pId = itm['productId'];
        final String? vId = itm['variantId'];
        final int itemCompleted =
            int.tryParse(itm['completedQuantity']?.toString() ?? '0') ?? 0;

        if (pId != null &&
            vId != null &&
            pId != 'null' &&
            vId != 'null' &&
            itemCompleted > 0) {
          await updateInventory(
            productId: pId,
            variantId: vId,
            change: itemCompleted,
            movementType: 'production',
            referenceId: '${batchId}_${entry.key}',
          );
          totalCompleted += itemCompleted;
        }
      }
      await batchRef.update({'inventoryAddedQuantity': totalCompleted});
      return true;
    }

    return false;
  }

  // --- ORDERS ---
  Stream<DatabaseEvent> getOrdersStream() => _watch('orders');

  Future<void> updateOrderStatus(String orderId, String status) async {
    if (status == 'Completed') {
      await completeOrder(orderId);
    } else {
      final updates = <String, dynamic>{'orderStatus': status};
      // Stamp readyForPickupAt atomically with the status change so both
      // fields are always in sync — prevents a stale timestamp if the app
      // crashes between two separate writes.
      if (status == 'Ready for Pickup') {
        updates['readyForPickupAt'] = ServerValue.timestamp;
      }
      await _db.child('orders').child(orderId).update(updates);
    }
  }

  Future<void> completeOrder(String orderId) async {
    final orderRef = _db.child('orders').child(orderId);
    final snap = await orderRef.get();
    if (!snap.exists) return;

    final data = Map<String, dynamic>.from(snap.value as Map);

    // ── Idempotency guard ────────────────────────────────────────────────────
    // New orders use productQtyDeducted.
    // Legacy orders that already ran against inventoryDeducted are also blocked
    // so they cannot re-run via the new path.
    if (data['productQtyDeducted'] == true) return;
    if (data['inventoryDeducted'] == true) {
      // Legacy order already processed — just finalize the status fields
      // without touching any quantities again.
      await orderRef.update({
        'orderStatus': 'Completed',
        'paymentStatus': 'Paid',
      });
      return;
    }

    // Lock the order BEFORE deducting to prevent double-deduction if the app
    // crashes mid-loop.  We set productQtyDeducted pessimistically.
    await orderRef.update({'productQtyDeducted': true});

    final items = data['items'] as Map?;
    if (items != null) {
      for (final entry in items.entries) {
        final item = Map<String, dynamic>.from(entry.value as Map);
        final String productId = item['productId'] as String? ?? '';
        final String variantId = item['variantId'] as String? ?? '';
        final int orderQty = (item['quantity'] as num?)?.toInt() ?? 0;

        if (productId.isEmpty || variantId.isEmpty || orderQty <= 0) continue;

        // Atomically deduct from products/{pId}/variants/{vId}/productQuantity.
        // Never deduct from inventory/ — that pool belongs to the Inventory module.
        final varRef = _db
            .child('products')
            .child(productId)
            .child('variants')
            .child(variantId);

        await varRef.runTransaction((Object? current) {
          if (current == null) return Transaction.abort();
          final vData = Map<String, dynamic>.from(current as Map);
          final int currentPQ =
              (vData['productQuantity'] as num?)?.toInt() ?? 0;
          final int newPQ = (currentPQ - orderQty).clamp(0, 999999);
          vData['productQuantity'] = newPQ;
          return Transaction.success(vData);
        });
      }
    }

    await orderRef.update({
      'orderStatus': 'Completed',
      'paymentStatus': 'Paid',
    });

    await createNotification(
      type: 'NEW_SALE',
      message: 'Order #$orderId marked as completed.',
      relatedId: orderId,
    );
  }

  Future<void> verifyPayment(String orderId) async {
    await _db.child('orders').child(orderId).update({
      'paymentStatus': 'Paid',
      'paymentVerifiedAt': ServerValue.timestamp,
      'paymentVerifiedBy': _currentUserId,
    });

    await createNotification(
      type: 'PAYMENT_VERIFIED',
      message: 'Payment for Order #$orderId has been verified.',
      relatedId: orderId,
    );
  }

  Future<void> updatePaymentStatus(
    String orderId,
    String status, {
    String? rejectionReason,
  }) async {
    final updates = <String, dynamic>{
      'paymentStatus': status,
      'paymentVerifiedAt': ServerValue.timestamp,
      'paymentVerifiedBy': _currentUserId,
    };
    if (rejectionReason != null) {
      updates['paymentRejectionReason'] = rejectionReason;
    }
    if (status == 'Confirmed' || status == 'Paid') {
      // Only advance orderStatus to 'Confirmed' if it hasn't already been
      // Completed — prevents payment confirmation from reverting a finished order.
      final orderSnap = await _db.child('orders').child(orderId).get();
      if (orderSnap.exists) {
        final currentStatus = (Map<String, dynamic>.from(
          orderSnap.value as Map,
        ))['orderStatus'];
        if (currentStatus != 'Completed') {
          updates['orderStatus'] = 'Confirmed';
        }
      }
    }
    await _db.child('orders').child(orderId).update(updates);

    await createNotification(
      type: status == 'Confirmed' || status == 'Paid'
          ? 'PAYMENT_VERIFIED'
          : 'PAYMENT_REJECTED',
      message: 'Payment for Order #$orderId has been $status.',
      relatedId: orderId,
    );
  }

  // --- IOT SCAN ---
  Stream<DatabaseEvent> getScanResultsStream() => _watch('scan_results');

  // ── IOT SCAN — BOTTLE-SIZE-LEVEL ARCHITECTURE ──────────────────────────────
  //
  // THESIS SCOPE: The ESP32-CAM reports physical bottle counts grouped by
  // bottle SIZE only. It does NOT identify honey variety (Pukyutan, Atis, etc.).
  //
  // The correct comparison flow is:
  //   ESP32 detects: { "250g": 14 }
  //   System expected: Pukyutan 250g (10) + Atis 250g (5) = 15 total
  //   Difference: -1
  //   Report: "1-bottle discrepancy for 250g bottles."
  //
  // The system NEVER deduces which specific product/variant is missing from
  // a size-level discrepancy — that requires human investigation.
  //
  // LOW-STOCK monitoring uses bottle_size_thresholds/ — a dedicated node with
  // per-size thresholds configured by the admin. This is separate from the
  // per-variant reorderLevel used by product inventory.

  // ── bottle_size_thresholds/ ──────────────────────────────────────────────
  //   Structure:
  //     bottle_size_thresholds/{sizeKey}/
  //       size: "250g"
  //       lowStockThreshold: 15
  //       updatedAt: timestamp
  //
  // sizeKey is the size string URL-encoded (dots/spaces replaced with underscores).

  Stream<DatabaseEvent> getBottleSizeThresholdsStream() =>
      _watch('bottle_size_thresholds');

  /// Creates or updates the low-stock threshold for a specific bottle size.
  Future<void> upsertBottleSizeThreshold({
    required String size,
    required int lowStockThreshold,
    required String adminName,
  }) async {
    final key = _sizeToKey(size);
    await _db.child('bottle_size_thresholds').child(key).set({
      'size': size,
      'lowStockThreshold': lowStockThreshold,
      'updatedAt': ServerValue.timestamp,
      'updatedBy': _currentUserId,
    });
    await logAdminActivity(
      action: 'SET_BOTTLE_SIZE_THRESHOLD',
      details:
          '$adminName set low-stock threshold for $size → $lowStockThreshold bottles.',
    );
  }

  /// Deletes the threshold configuration for a bottle size.
  Future<void> deleteBottleSizeThreshold(String size) async {
    await _db.child('bottle_size_thresholds').child(_sizeToKey(size)).remove();
  }

  /// Converts a size string to a safe Firebase key.
  /// e.g. "250g" → "250g", "1.5kg" → "1_5kg", "Honey With Pollen 500g" → "Honey_With_Pollen_500g"
  String _sizeToKey(String size) =>
      size.trim().replaceAll(RegExp(r'[.\s/]'), '_');

  // ── Aggregate system quantity by bottle size ─────────────────────────────
  //
  // Returns a map of { size → totalSystemQty } by summing inventory quantities
  // across ALL active product variants that share a given bottle size.
  //
  // Example:
  //   Pukyutan 250g inventory: 10
  //   Atis Malupera 250g inventory: 5
  //   → { "250g": 15 }
  //
  // This is the number the ESP32 scan should be compared against for 250g.
  Future<Map<String, int>> aggregateSysQtyBySize() async {
    final productsSnap = await _db.child('products').get();
    final inventorySnap = await _db.child('inventory').get();

    if (!productsSnap.exists || productsSnap.value == null) return {};

    final products = Map<String, dynamic>.from(productsSnap.value as Map);
    final invMap = inventorySnap.exists && inventorySnap.value is Map
        ? Map<String, dynamic>.from(inventorySnap.value as Map)
        : <String, dynamic>{};

    final Map<String, int> sysQtyBySize = {};

    products.forEach((pId, pVal) {
      if (pVal is! Map) return;
      final variants = (pVal['variants'] as Map?) ?? {};
      variants.forEach((vId, vVal) {
        if (vVal is! Map) return;
        if (vVal['isActive'] == false) return; // skip inactive variants
        final String size = (vVal['size'] ?? '').toString();
        if (size.isEmpty) return;
        final invVariant = ((invMap[pId] as Map?) ?? {})[vId] as Map?;
        final int qty = (invVariant?['quantity'] as num?)?.toInt() ?? 0;
        sysQtyBySize[size] = (sysQtyBySize[size] ?? 0) + qty;
      });
    });

    return sysQtyBySize;
  }

  /// After the ESP32 writes a scan_result with detectedSizes, this method
  /// enriches it with the aggregated system quantities, per-size comparisons,
  /// and overall status. It also fires low-stock notifications if thresholds
  /// are configured.
  ///
  /// Call this once after the ESP32 completes a scan and the scan_result node
  /// exists in Firebase.
  Future<void> updateScanResultWithComparisons(String scanId) async {
    final scanRef = _db.child('scan_results').child(scanId);
    final scanSnap = await scanRef.get();
    if (!scanSnap.exists || scanSnap.value == null) return;

    final scanData = Map<String, dynamic>.from(scanSnap.value as Map);
    final detectedSizes = scanData['detectedSizes'];
    if (detectedSizes is! Map || detectedSizes.isEmpty) return;

    // Aggregate system quantities by size
    final sysQtyBySize = await aggregateSysQtyBySize();

    // Load bottle-size thresholds for low-stock checks
    final thresholdSnap = await _db.child('bottle_size_thresholds').get();
    final thresholds = <String, int>{};
    if (thresholdSnap.exists && thresholdSnap.value is Map) {
      (thresholdSnap.value as Map).forEach((_, v) {
        if (v is! Map) return;
        final size = v['size']?.toString() ?? '';
        final t = (v['lowStockThreshold'] as num?)?.toInt() ?? 0;
        if (size.isNotEmpty && t > 0) thresholds[size] = t;
      });
    }

    // Build per-size comparisons — no productId/variantId needed
    final Map<String, dynamic> comparisons = {};
    bool hasAnyMismatch = false;
    int totalDetected = 0;

    detectedSizes.forEach((size, countRaw) {
      final int physical = (countRaw as num?)?.toInt() ?? 0;
      final int system = sysQtyBySize[size.toString()] ?? 0;
      final int diff = physical - system;
      final String status = diff == 0 ? 'MATCH' : 'MISMATCH';
      totalDetected += physical;
      if (status == 'MISMATCH') hasAnyMismatch = true;

      comparisons[size.toString()] = {
        'physical': physical,
        'system': system,
        'diff': diff,
        'status': status,
        // Intentionally NO productId/variantId — the ESP32 cannot identify variety.
      };
    });

    final String overallStatus = hasAnyMismatch ? 'PARTIAL_MISMATCH' : 'MATCH';

    // Write enriched data back to the scan result
    await scanRef.update({
      'comparisons': comparisons,
      'overallStatus': overallStatus,
      'totalDetected': totalDetected,
      'systemQtySnapshot': sysQtyBySize, // snapshot for audit trail
    });

    // ── Notifications ──────────────────────────────────────────────────────
    // 1. Mismatch notification
    if (hasAnyMismatch) {
      final mismatchSizes = comparisons.entries
          .where((e) => (e.value as Map)['status'] == 'MISMATCH')
          .map(
            (e) =>
                '${e.key} (detected: ${(e.value as Map)['physical']}, '
                'system: ${(e.value as Map)['system']}, '
                'diff: ${(e.value as Map)['diff'] > 0 ? '+' : ''}${(e.value as Map)['diff']})',
          )
          .join(', ');
      await createNotification(
        type: 'SCAN_MISMATCH',
        message:
            'Physical count discrepancy detected — $mismatchSizes. '
            'Review in Inventory → Verification.',
        relatedId: scanId,
      );
    }

    // 2. Low-stock notification per size (uses bottle_size_thresholds/)
    for (final entry in comparisons.entries) {
      final size = entry.key;
      final physical = (entry.value as Map)['physical'] as int;
      final threshold = thresholds[size];
      if (threshold != null && physical <= threshold) {
        await createNotification(
          type: 'BOTTLE_LOW_STOCK',
          message:
              'Low physical bottle stock — $size: '
              '$physical bottles detected (threshold: $threshold). '
              'Consider replenishing bottle supply.',
          relatedId: scanId,
        );
      }
    }
  }

  /// Records an ESP32-CAM physical stock scan without altering System Inventory.
  ///
  /// DEPRECATED — this legacy path requires productId/variantId which the
  /// ESP32-CAM cannot determine. It contradicts the thesis architecture where
  /// the camera only identifies bottle SIZE, not honey variety.
  ///
  /// Use the new flow instead:
  ///   1. ESP32 writes directly to scan_results/ with detectedSizes map.
  ///   2. Call updateScanResultWithComparisons(scanId) to enrich with system qty.
  ///
  /// Kept for backward compatibility with older scan_results records only.
  @Deprecated(
    'Use scan_results/{id}/detectedSizes + updateScanResultWithComparisons()',
  )
  Future<String> recordIotScanResult({
    required String productId,
    required String variantId,
    required String productName,
    required String bottleSize,
    required int detectedQty,
  }) async {
    final invRef = _db.child('inventory').child(productId).child(variantId);
    final invSnap = await invRef.get();
    int systemQty = 0;
    if (invSnap.exists && invSnap.value is Map) {
      systemQty = (invSnap.value as Map)['quantity'] ?? 0;
    }

    final int difference = detectedQty - systemQty;
    final String status = (detectedQty == systemQty) ? 'MATCH' : 'MISMATCH';

    final ref = _db.child('scan_results').push();
    await ref.set({
      'id': ref.key,
      'bottleSize': bottleSize, // kept; productName/Id removed from new path
      'detectedQuantity': detectedQty,
      'systemQuantity': systemQty,
      'difference': difference,
      'status': status,
      'scanTimestamp': ServerValue.timestamp,
      'isAcknowledged': false,
      'recordedBy': _currentUserId,
      // Legacy fields — do NOT use for new scans:
      '_legacy': true,
      'productId': productId,
      'variantId': variantId,
      'productName': productName,
    });

    // DO NOT modify system inventory. Physical scan is monitoring only.
    return ref.key!;
  }

  /// Acknowledges a scan result — marks it reviewed with no inventory change.
  Future<void> verifyScan(String scanId) async {
    final scanRef = _db.child('scan_results').child(scanId);
    await scanRef.update({
      'isAcknowledged': true,
      'verifiedBy': _currentUserId,
      'verifiedTimestamp': ServerValue.timestamp,
    });
  }

  Future<void> rejectScan(String scanId) async {
    await _db.child('scan_results').child(scanId).update({
      'status': 'Rejected',
      'isAcknowledged': true,
      'verifiedBy': _currentUserId,
      'verifiedTimestamp': ServerValue.timestamp,
    });
  }

  /// DEPRECATED — directly adjusting inventory from an ESP32 size-level
  /// discrepancy is architecturally incorrect because the camera cannot
  /// identify which honey variety a bottle belongs to.
  ///
  /// The correct path for a discrepancy is:
  ///   1. Admin reviews the size-level mismatch in Verification tab.
  ///   2. Admin physically investigates (which product/variant is off?).
  ///   3. Admin uses Stock Corrections tab to apply the specific product adjustment.
  ///
  /// This method now only acknowledges the scan — it does NOT touch inventory.
  Future<void> reconcileScanDiscrepancy(String scanId) async {
    final scanRef = _db.child('scan_results').child(scanId);
    await scanRef.update({
      'isAcknowledged': true,
      'acknowledgedBy': _currentUserId,
      'acknowledgedAt': ServerValue.timestamp,
      'status': 'REVIEWED',
    });
    await logAdminActivity(
      action: 'ACKNOWLEDGE_SCAN_DISCREPANCY',
      details:
          'Admin reviewed scan #$scanId size discrepancy. '
          'No inventory modified. Use Stock Corrections for any adjustments.',
    );
  }

  // --- SUPPLIERS ---
  Stream<DatabaseEvent> getSuppliersStream() => _watch('suppliers');

  Future<void> addSupplier(
    Map<String, dynamic> supplierData, [
    String? performerName,
  ]) async {
    final ref = _db.child('suppliers').push();
    await ref.set({
      ...supplierData,
      'id': ref.key,
      'createdTimestamp': ServerValue.timestamp,
      'createdBy': _currentUserId,
    });
    if (performerName != null) {
      await logAdminActivity(
        action: 'ADD_SUPPLIER',
        details:
            'Added supplier ${supplierData['supplierName'] ?? ''} by $performerName',
      );
    }
  }

  Future<void> updateSupplier(
    String supplierId,
    Map<String, dynamic> supplierData, [
    String? performerName,
  ]) async {
    await _db.child('suppliers').child(supplierId).update({
      ...supplierData,
      'updatedTimestamp': ServerValue.timestamp,
    });
    if (performerName != null) {
      await logAdminActivity(
        action: 'UPDATE_SUPPLIER',
        details: 'Updated supplier $supplierId by $performerName',
      );
    }
  }

  Future<void> deleteSupplier(
    String supplierId, [
    String? supplierName,
    String? performerName,
  ]) async {
    await _db.child('suppliers').child(supplierId).remove();
    if (performerName != null) {
      await logAdminActivity(
        action: 'DELETE_SUPPLIER',
        details:
            'Deleted supplier ${supplierName ?? supplierId} by $performerName',
      );
    }
  }

  // --- ADMIN ACTIVITY LOGS ---
  //
  // Supabase is the primary (authoritative) destination.
  // Firebase RTDB is the secondary archive — preserved for historical records
  // but no longer authoritative. If Firebase fails, the Supabase record
  // already exists so the log is not lost; the error is reported to the
  // caller rather than swallowed silently.
  //
  // Identity note: the Supabase RPC uses auth.uid() from the Supabase JWT
  // (the admin's Supabase UUID). The Firebase write continues to use
  // _currentUserId (Firebase Auth uid) for the archive only.
  Future<void> logAdminActivity({
    required String action,
    required String details,
  }) async {
    // ── Step 1: Supabase (primary) ────────────────────────────────────────────
    // The RPC validates active admin status, trims and clamps inputs, and
    // records auth.uid() as the admin_id. It throws on any failure.
    try {
      await Supabase.instance.client.rpc(
        'log_admin_activity',
        params: {'p_action': action, 'p_details': details},
      );
    } catch (e) {
      debugPrint('[DatabaseService] Supabase logAdminActivity failed: $e');
      // Re-throw so callers know the primary write did not succeed.
      // This prevents misleading success signals for critical audit events.
      rethrow;
    }

    // ── Step 2: Firebase RTDB (secondary archive) ─────────────────────────────
    // Best-effort mirror for historical continuity. Firebase failures do not
    // cause a rethrow because Supabase already holds the authoritative record.
    try {
      final ref = _db.child('admin_activity_logs').push();
      await ref.set({
        'id': ref.key,
        'adminId': _currentUserId, // Firebase Auth uid (archive only)
        'action': action,
        'details': details,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      // Log the inconsistency but do not rethrow — Supabase succeeded.
      debugPrint(
        '[DatabaseService] Firebase activity log archive failed '
        '(Supabase record is authoritative and intact): $e',
      );
    }
  }

  // --- NOTIFICATIONS ---
  Stream<DatabaseEvent> getNotificationsStream() => _watch('notifications');

  Future<void> createNotification({
    required String type,
    required String message,
    String? relatedId,
  }) async {
    await SupabaseNotificationService.instance.createFromAdmin(
      type: type,
      message: message,
      relatedId: relatedId,
    );
  }

  Future<void> markNotificationAsRead(
    String notificationId, [
    String? targetUserId,
  ]) async {
    await SupabaseNotificationService.instance.markAsRead(notificationId);
  }

  // --- PRODUCTION EXTENSIONS (Bulk & Progress) ---
  Future<void> createBulkProductionBatch(Map<String, dynamic> bulkData) async {
    final ref = _db.child('production_batches').push();
    await ref.set({
      ...bulkData,
      'id': ref.key,
      'createdTimestamp': ServerValue.timestamp,
      'createdBy': _currentUserId,
    });
  }

  Future<void> updateProductionItemProgress({
    required String batchId,
    required String itemId,
    required int completedQty,
  }) async {
    final batchRef = _db.child('production_batches').child(batchId);
    final snap = await batchRef.get();
    if (!snap.exists) return;

    final data = Map<String, dynamic>.from(snap.value as Map);
    if (data['isArchived'] == true) {
      print(
        '[DEBUG] updateProductionItemProgress: batch $batchId is archived. Skipping update.',
      );
      return;
    }

    final bool isBundle = data['isBundle'] == true;

    if (!isBundle) {
      int target = data['quantityTarget'] ?? data['quantityProduced'] ?? 0;
      if (completedQty < 0) completedQty = 0;

      final bool isAlreadyUpdated =
          data['inventoryUpdated'] == true || data['status'] == 'Completed';

      if (isAlreadyUpdated) {
        // EDITING A COMPLETED PRODUCTION
        int previousAddedQty =
            data['inventoryAddedQuantity'] ?? data['completedQuantity'] ?? 0;
        int diff = completedQty - previousAddedQty;

        print(
          '[DEBUG] Editing Completed Production $batchId: previousAdded=$previousAddedQty, newQty=$completedQty, diff=$diff',
        );

        if (diff != 0) {
          final String? productId = data['productId'];
          final String? variantId = data['variantId'];

          if (productId != null &&
              variantId != null &&
              productId != 'null' &&
              variantId != 'null') {
            bool success = await updateInventory(
              productId: productId,
              variantId: variantId,
              change: diff,
              movementType: 'production_adjustment',
              referenceId: batchId,
            );

            if (!success) {
              print(
                '[ERROR] updateProductionItemProgress: inventory update failed for batch $batchId',
              );
              return;
            }
          }
        }

        final historyRef = batchRef.child('history').push();
        await historyRef.set({
          'id': historyRef.key,
          'previousCompletedQuantity': previousAddedQty,
          'newCompletedQuantity': completedQty,
          'inventoryAdjustment': diff,
          'editedBy': _currentUserId,
          'timestamp': ServerValue.timestamp,
        });

        await batchRef.update({
          'completedQuantity': completedQty,
          'inventoryAddedQuantity': completedQty,
          'inventoryUpdated': true,
          'status': 'Completed',
          'lastEditedBy': _currentUserId,
          'lastEditedAt': ServerValue.timestamp,
        });

        await logAdminActivity(
          action: 'EDIT_COMPLETED_PRODUCTION',
          details:
              'Edited completed quantity for batch #$batchId from $previousAddedQty to $completedQty (inventory adjustment: $diff)',
        );
      } else {
        // NOT YET COMPLETED PRODUCTION
        String status = 'In Progress';
        if (completedQty == 0) {
          status = 'Planned';
        } else if (target > 0 && completedQty >= target) {
          status = 'Completed';
        } else {
          status = 'Partially Completed';
        }

        await batchRef.update({
          'completedQuantity': completedQty,
          'status': status,
        });

        // Condition 6: Inventory is updated ONLY when completedQuantity >= targetQuantity and inventoryUpdated != true
        if (target > 0 &&
            completedQty >= target &&
            data['inventoryUpdated'] != true) {
          await completeProduction(batchId);
        }
      }
    } else {
      // BUNDLE BATCH
      final items = Map<String, dynamic>.from(data['items'] ?? {});
      if (items.containsKey(itemId)) {
        final item = Map<String, dynamic>.from(items[itemId]);
        if (completedQty < 0) completedQty = 0;

        final bool isAlreadyUpdated =
            data['inventoryUpdated'] == true || data['status'] == 'Completed';

        if (isAlreadyUpdated) {
          int prevItemQty = item['completedQuantity'] ?? 0;
          int diff = completedQty - prevItemQty;

          if (diff != 0) {
            final String? pId = item['productId'];
            final String? vId = item['variantId'];

            if (pId != null && vId != null && pId != 'null' && vId != 'null') {
              bool success = await updateInventory(
                productId: pId,
                variantId: vId,
                change: diff,
                movementType: 'production_adjustment',
                referenceId: '${batchId}_$itemId',
              );

              if (!success) return;
            }
          }

          item['completedQuantity'] = completedQty;
          items[itemId] = item;

          int totalCompleted = 0;
          items.forEach((k, v) {
            final itm = Map<String, dynamic>.from(v);
            totalCompleted += (itm['completedQuantity'] ?? 0) as int;
          });

          final historyRef = batchRef.child('history').push();
          await historyRef.set({
            'id': historyRef.key,
            'itemId': itemId,
            'previousCompletedQuantity': prevItemQty,
            'newCompletedQuantity': completedQty,
            'inventoryAdjustment': diff,
            'editedBy': _currentUserId,
            'timestamp': ServerValue.timestamp,
          });

          await batchRef.update({
            'items': items,
            'quantityCompleted': totalCompleted,
            'inventoryAddedQuantity': totalCompleted,
            'inventoryUpdated': true,
            'status': 'Completed',
            'lastEditedBy': _currentUserId,
            'lastEditedAt': ServerValue.timestamp,
          });

          await logAdminActivity(
            action: 'EDIT_COMPLETED_PRODUCTION',
            details:
                'Edited completed quantity for bulk item $itemId in batch #$batchId from $prevItemQty to $completedQty (inventory adjustment: $diff)',
          );
        } else {
          item['completedQuantity'] = completedQty;
          items[itemId] = item;

          int totalCompleted = 0;
          int totalTarget = 0;
          items.forEach((k, v) {
            final itm = Map<String, dynamic>.from(v);
            totalCompleted += (itm['completedQuantity'] ?? 0) as int;
            totalTarget +=
                (itm['targetQuantity'] ?? itm['quantityProduced'] ?? 0) as int;
          });

          String overallStatus = 'In Progress';
          if (totalCompleted == 0) {
            overallStatus = data['status'] ?? 'Preparing';
          } else if (totalCompleted >= totalTarget) {
            overallStatus = 'Completed';
          } else {
            overallStatus = 'Partially Completed';
          }

          await batchRef.update({
            'items': items,
            'quantityProduced': totalCompleted,
            'quantityCompleted': totalCompleted,
            'status': overallStatus,
          });

          if (totalTarget > 0 &&
              totalCompleted >= totalTarget &&
              data['inventoryUpdated'] != true) {
            await completeProduction(batchId);
          }
        }
      }
    }
  }

  Future<void> archiveProductionBatch(String batchId) async {
    final batchRef = _db.child('production_batches').child(batchId);
    await batchRef.update({
      'isArchived': true,
      'archivedAt': ServerValue.timestamp,
    });
    await logAdminActivity(
      action: 'ARCHIVE_PRODUCTION_BATCH',
      details: 'Archived production batch #$batchId',
    );
  }

  /// Safely resets test Production batches and related Inventory data.
  /// Does NOT delete real/user data, Firebase Auth accounts, database structure, or products.
  Future<Map<String, dynamic>> resetTestProductionAndInventoryData() async {
    print('[RESET] Resetting test production batches and inventory data...');

    // 1. Reset all inventory stock quantities to 0
    final invSnap = await _db.child('inventory').get();
    int resetInventoryCount = 0;
    if (invSnap.exists && invSnap.value is Map) {
      final inventoryMap = Map<String, dynamic>.from(invSnap.value as Map);
      final Map<String, dynamic> resetInventoryMap = {};
      inventoryMap.forEach((pId, pVars) {
        if (pVars is Map) {
          final varsMap = Map<String, dynamic>.from(pVars);
          final Map<String, dynamic> resetVars = {};
          varsMap.forEach((vId, vData) {
            resetVars[vId] = {
              'quantity': 0,
              'lastUpdated': ServerValue.timestamp,
            };
            resetInventoryCount++;
          });
          resetInventoryMap[pId] = resetVars;
        }
      });
      await _db.child('inventory').set(resetInventoryMap);
    }

    // 2. Clear test production batches
    final prodSnap = await _db.child('production_batches').get();
    int resetBatchCount = 0;
    if (prodSnap.exists && prodSnap.value is Map) {
      resetBatchCount = (prodSnap.value as Map).length;
      await _db.child('production_batches').remove();
    }

    // 3. Clear test inventory movements
    final movSnap = await _db.child('inventory_movements').get();
    int resetMovementCount = 0;
    if (movSnap.exists && movSnap.value is Map) {
      resetMovementCount = (movSnap.value as Map).length;
      await _db.child('inventory_movements').remove();
    }

    // 4. Log admin activity
    await logAdminActivity(
      action: 'RESET_TEST_DATA',
      details:
          'Reset test production batches ($resetBatchCount), inventory levels ($resetInventoryCount variants to 0), and inventory movements ($resetMovementCount).',
    );

    return {
      'batchesReset': resetBatchCount,
      'inventoryVariantsReset': resetInventoryCount,
      'movementsReset': resetMovementCount,
      'startingInventoryQuantity': 0,
    };
  }

  // --- ADDITIONAL ADMIN STREAMS & HELPERS ---
  Stream<DatabaseEvent> getCustomersStream() => _watch('customers');
  Stream<DatabaseEvent> getSalesStream() => _watch('sales');
  Stream<DatabaseEvent> getAdminsStream() => _watch('admins');
  Stream<DatabaseEvent> getAdminActivityLogsStream() =>
      _watch('admin_activity_logs');

  Future<void> updateAdminStatus(
    String adminId,
    dynamic status, [
    String? performerUid,
    String? performerName,
  ]) async {
    final statusStr = status is bool
        ? (status ? 'active' : 'inactive')
        : status.toString();
    await _db.child('admins').child(adminId).update({
      'status': statusStr,
      'isActive': statusStr == 'active',
    });
    if (performerName != null) {
      await logAdminActivity(
        action: 'UPDATE_ADMIN_STATUS',
        details:
            'Updated status of admin $adminId to $statusStr by $performerName',
      );
    }
  }

  @Deprecated(
    'Remove after the Supabase pickup-followup migration is deployed and verified.',
  )
  Future<void> sendPickupReminder({
    required String orderId,
    required String customerName,
    required String customerEmail,
    String? customerId,
  }) async {
    final shortId = orderId.length >= 6
        ? 'HB-${orderId.substring(0, 6).toUpperCase()}'
        : orderId.toUpperCase();
    final message =
        'Hi $customerName! 🐝\n\n'
        'Friendly reminder from Honeybee Center:\n'
        'Your order #$shortId is ready for pickup at our store!\n\n'
        '📍 Pickup Location: Honeybee Center Store\n'
        '⏰ Store Hours: 9:00 AM – 6:00 PM (Monday to Saturday)\n\n'
        'Please present this Order Reference upon arrival so we can hand over your items promptly.\n\n'
        'Thank you, and see you soon!';
    final conversationId = await createConversation(
      customerName: customerName,
      customerEmail: customerEmail,
      customerId: customerId,
      orderId: orderId,
    );
    final ref = _db
        .child('conversations')
        .child(conversationId)
        .child('messages')
        .push();
    await ref.set({
      'id': ref.key,
      'message': message,
      'text': message,
      'senderId': 'system',
      'senderRole': 'system',
      'senderName': 'Honeybee Center',
      'isAutomated': true,
      'timestamp': ServerValue.timestamp,
      'read': false,
    });
    await _db.child('conversations').child(conversationId).update({
      'lastMessage': message,
      'lastMessageTime': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      'isRead': false,
    });
    await _db.child('orders').child(orderId).update({
      'pickupReminderSent': true,
      'pickupReminderSentAt': ServerValue.timestamp,
    });
  }

  @Deprecated(
    'Remove after the Supabase pickup-followup migration is deployed and verified.',
  )
  Future<String> createConversation({
    required String customerName,
    required String customerEmail,
    String? customerId,
    String? orderId,
  }) async {
    final existing = await _db.child('conversations').get();
    if (existing.exists && existing.value is Map) {
      final map = Map<String, dynamic>.from(existing.value as Map);
      for (final entry in map.entries) {
        final conversation = Map<String, dynamic>.from(
          entry.value as Map? ?? {},
        );
        final emailMatches =
            (conversation['customerEmail'] ?? '').toString().toLowerCase() ==
            customerEmail.toLowerCase();
        if (emailMatches &&
            conversation['orderId'] == orderId &&
            conversation['status'] != 'resolved') {
          return entry.key;
        }
      }
    }

    final ref = _db.child('conversations').push();
    await ref.set({
      'id': ref.key,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'customerId': customerId,
      'orderId': orderId,
      'status': 'open',
      'lastMessage': '',
      'isRead': false,
      'createdAt': ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
    });
    return ref.key!;
  }

  Future<void> markAllNotificationsRead() async {
    await SupabaseNotificationService.instance.markAllAsRead();
  }

  Future<void> updateProductionStatus({
    required String batchId,
    required String status,
  }) async {
    await _db.child('production_batches').child(batchId).update({
      'status': status,
    });
  }

  // --- FEEDBACK / REVIEWS ---

  /// Stream of all customer feedback entries, ordered by timestamp.
  Stream<DatabaseEvent> getFeedbackStream() => _watch('feedback');

  /// Submits a new customer feedback/review entry.
  Future<void> submitFeedback({
    required String customerName,
    required String customerEmail,
    required int rating, // 1–5 stars
    required String message,
    String? orderId,
    String? productName,
  }) async {
    final ref = _db.child('feedback').push();
    await ref.set({
      'id': ref.key,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'rating': rating,
      'message': message,
      'orderId': orderId,
      'productName': productName,
      'timestamp': ServerValue.timestamp,
      'isArchived': false,
      'isRead': false,
      'adminReply': null,
      'repliedAt': null,
    });
  }

  /// Marks a feedback entry as read.
  Future<void> markFeedbackRead(String feedbackId) async {
    await _db.child('feedback').child(feedbackId).update({'isRead': true});
  }

  /// Archives or unarchives a feedback entry.
  Future<void> archiveFeedback(String feedbackId, {bool archive = true}) async {
    await _db.child('feedback').child(feedbackId).update({
      'isArchived': archive,
    });
  }

  /// Saves an admin reply to a feedback entry.
  Future<void> replyToFeedback(String feedbackId, String reply) async {
    await _db.child('feedback').child(feedbackId).update({
      'adminReply': reply,
      'repliedAt': ServerValue.timestamp,
      'isRead': true,
    });
  }

  /// Marks all unread feedback as read.
  Future<void> markAllFeedbackRead() async {
    final snap = await _db.child('feedback').get();
    if (!snap.exists || snap.value == null) return;
    final map = Map<String, dynamic>.from(snap.value as Map);
    for (final key in map.keys) {
      await _db.child('feedback').child(key).update({'isRead': true});
    }
  }

  // ── PRODUCT QUANTITY ─────────────────────────────────────────────────────

  /// Transfers [qty] units from Inventory to Product Quantity.
  ///
  /// Atomic rules:
  ///   - inventory/{pId}/{vId}/quantity   decreases by [qty]
  ///   - products/{pId}/variants/{vId}/productQuantity  increases by [qty]
  ///
  /// Returns a [AddResult] describing success or the specific failure
  /// reason so the UI can show an appropriate message.
  ///
  /// Prevents:
  ///   - Inventory going below 0
  ///   - [qty] <= 0
  Future<AddResult> addProductQuantity({
    required String productId,
    required String variantId,
    required int qty,
    required String adminName,
  }) async {
    if (qty <= 0) return AddResult.invalidQty;

    // ── Step 1: atomically deduct from inventory ──────────────────────────
    final invRef = _db.child('inventory').child(productId).child(variantId);
    int prevInvQty = 0;
    int newInvQty = 0;

    final invResult = await invRef.runTransaction((Object? current) {
      if (current == null) {
        // Inventory node doesn't exist — nothing to transfer.
        return Transaction.abort();
      }
      final data = Map<String, dynamic>.from(current as Map);
      final int currentQty = (data['quantity'] as num?)?.toInt() ?? 0;
      if (currentQty < qty) {
        // Not enough inventory — abort without changing anything.
        return Transaction.abort();
      }
      prevInvQty = currentQty;
      newInvQty = currentQty - qty;
      data['quantity'] = newInvQty;
      data['lastUpdated'] = ServerValue.timestamp;
      return Transaction.success(data);
    });

    if (!invResult.committed) {
      // Determine why: read inventory to tell the UI the actual available qty.
      final checkSnap = await invRef.get();
      if (!checkSnap.exists) return AddResult.noInventoryNode;
      final avail = ((checkSnap.value as Map?) ?? {})['quantity'] as int? ?? 0;
      if (avail < qty) return AddResult.insufficientInventory(avail);
      return AddResult.transactionFailed;
    }

    // ── Step 2: increase productQuantity on the variant ──────────────────
    final varRef = _db
        .child('products')
        .child(productId)
        .child('variants')
        .child(variantId);

    int prevPQ = 0;
    int newPQ = 0;

    final pqResult = await varRef.runTransaction((Object? current) {
      if (current == null) return Transaction.abort();
      final data = Map<String, dynamic>.from(current as Map);
      prevPQ = (data['productQuantity'] as num?)?.toInt() ?? 0;
      newPQ = prevPQ + qty;
      data['productQuantity'] = newPQ;
      return Transaction.success(data);
    });

    if (!pqResult.committed) {
      // Rollback: put the inventory units back.
      await invRef.runTransaction((Object? current) {
        if (current == null) return Transaction.abort();
        final data = Map<String, dynamic>.from(current as Map);
        data['quantity'] = ((data['quantity'] as num?)?.toInt() ?? 0) + qty;
        data['lastUpdated'] = ServerValue.timestamp;
        return Transaction.success(data);
      });
      return AddResult.transactionFailed;
    }

    // ── Step 3: record the inventory movement ────────────────────────────
    final refId = 'add_${DateTime.now().millisecondsSinceEpoch}';
    await _createInventoryMovement(
      productId: productId,
      variantId: variantId,
      change: -qty,
      prevQty: prevInvQty,
      newQty: newInvQty,
      type: 'product_replenishment',
      refId: refId,
      reason: 'Product Quantity Add',
      notes:
          'Transferred $qty unit(s) to Product Quantity by $adminName. '
          'Product QTY: $prevPQ → $newPQ.',
    );

    // ── Step 4: admin activity log ────────────────────────────────────────
    await logAdminActivity(
      action: 'PRODUCT_QTY_REPLENISHMENT',
      details:
          'Replenished $qty unit(s) for $productId/$variantId by $adminName. '
          'Inventory: $prevInvQty → $newInvQty. '
          'Product QTY: $prevPQ → $newPQ.',
    );

    return AddResult.success;
  }

  // ── MANUAL INVENTORY ADJUSTMENTS ─────────────────────────────────────────

  /// Streams all inventory_movements records — used for the View History dialog
  /// and the Adjustments tab recent-history list.
  Stream<DatabaseEvent> getInventoryMovementsStream() =>
      _watch('inventory_movements');

  /// Applies a manual stock adjustment (increase or decrease) for a variant.
  ///
  /// [change]  positive = increase, negative = decrease.
  /// [reason]  must come from the approved reasons list.
  /// [notes]   optional free text.
  ///
  /// Writes:
  ///   inventory/{productId}/{variantId}/quantity  (via updateInventory transaction)
  ///   inventory_movements/{autoId}                 (reason + notes added)
  Future<bool> addManualAdjustment({
    required String productId,
    required String variantId,
    required int change,
    required String reason,
    String? notes,
    required String adminName,
  }) async {
    final refId = 'manual_${DateTime.now().millisecondsSinceEpoch}';

    // Run the atomic inventory transaction (reuses existing logic)
    final invRef = _db.child('inventory').child(productId).child(variantId);
    final result = await invRef.runTransaction((Object? value) {
      if (value == null) {
        return Transaction.success({
          'quantity': change < 0 ? 0 : change,
          'lastUpdated': ServerValue.timestamp,
        });
      }
      final data = Map<String, dynamic>.from(value as Map);
      int currentQty = data['quantity'] ?? 0;
      int newQty = (currentQty + change).clamp(0, 999999);
      data['quantity'] = newQty;
      data['lastUpdated'] = ServerValue.timestamp;
      return Transaction.success(data);
    });

    if (!result.committed) return false;

    final snapshot = Map<String, dynamic>.from(result.snapshot.value as Map);
    final int newQty = snapshot['quantity'];
    final int prevQty = newQty - change;

    // Write movement with reason + notes
    await _createInventoryMovement(
      productId: productId,
      variantId: variantId,
      change: change,
      prevQty: prevQty,
      newQty: newQty,
      type: 'manual_adjustment',
      refId: refId,
      reason: reason,
      notes: notes,
    );

    await _checkLowStock(productId, variantId, newQty);

    await logAdminActivity(
      action: 'MANUAL_INVENTORY_ADJUSTMENT',
      details:
          'Manual adjustment by $adminName: ${change > 0 ? '+' : ''}$change for $productId/$variantId. Reason: $reason.',
    );

    return true;
  }

  /// Updates a product variant's configuration (reorderLevel, isActive, and optionally price).
  /// Does NOT change size or id — those are immutable once set.
  Future<void> updateVariantConfig({
    required String productId,
    required String variantId,
    required int reorderLevel,
    required bool isActive,
    int? price,
  }) async {
    final updates = <String, dynamic>{
      'reorderLevel': reorderLevel,
      'isActive': isActive,
    };
    if (price != null && price > 0) updates['price'] = price;
    await _db
        .child('products')
        .child(productId)
        .child('variants')
        .child(variantId)
        .update(updates);
  }

  // ── IOT SCAN COMMANDS ─────────────────────────────────────────────────────

  /// Stream of all scan commands — used to detect active/completed commands
  /// and enforce the one-active-scan-at-a-time restriction.
  Stream<DatabaseEvent> getScanCommandsStream() => _watch('scan_commands');

  /// Stream of the ESP32 heartbeat — used for the 🟢/🔴 connection badge.
  Stream<DatabaseEvent> getIotStatusStream() => _watch('iot_status/esp32_main');

  /// Writes a new scan command with status "pending".
  /// Returns the new command ID so the UI can listen for its completion.
  ///
  /// The ESP32 firmware listens for pending commands, runs the scan,
  /// writes to scan_results/, and then updates this command's status
  /// to "completed".
  Future<String> createScanCommand({
    required String adminId,
    required String adminName,
  }) async {
    final callerId = _auth.currentUser?.uid ?? adminId;
    final ref = _db.child('scan_commands').push();
    await ref.set({
      'id': ref.key,
      'status': 'pending',
      'requestedBy': callerId,
      'requestedByName': adminName,
      'requestedAt': ServerValue.timestamp,
    });
    return ref.key!;
  }

  /// Marks a scan result as acknowledged (reviewed, no inventory change).
  /// Acknowledge means: "I have reviewed this scan and I am not changing
  /// inventory at this time."
  Future<void> acknowledgeScan(String scanId, String adminId) async {
    final callerId = _auth.currentUser?.uid ?? adminId;
    await _db.child('scan_results').child(scanId).update({
      'isAcknowledged': true,
      'acknowledgedBy': callerId,
      'acknowledgedAt': ServerValue.timestamp,
    });
  }

  /// Acknowledges a multi-size scan that had mismatches.
  ///
  /// ARCHITECTURE NOTE: This method does NOT adjust inventory. The ESP32-CAM
  /// reports counts by bottle size only — it cannot identify which honey variety
  /// a bottle belongs to. Therefore the system cannot legitimately decide
  /// "deduct 1 from Pukyutan" based on a size-level discrepancy.
  ///
  /// If a correction is needed, the admin must use the Stock Corrections tab
  /// to select the specific product/variant manually.
  Future<void> acknowledgeScanWithMismatches({
    required String scanId,
    required String adminId,
    required String adminName,
  }) async {
    final callerId = _auth.currentUser?.uid ?? adminId;
    await _db.child('scan_results').child(scanId).update({
      'isAcknowledged': true,
      'acknowledgedBy': callerId,
      'acknowledgedAt': ServerValue.timestamp,
      'status': 'REVIEWED',
    });

    await logAdminActivity(
      action: 'ACKNOWLEDGE_SCAN_WITH_MISMATCHES',
      details:
          'Admin $adminName reviewed size-level discrepancies in scan '
          '#${scanId.substring(0, scanId.length > 8 ? 8 : scanId.length).toUpperCase()}. '
          'No inventory modified. Manual Stock Corrections required if needed.',
    );
  }

  /// [DEPRECATED — DO NOT USE]
  /// Previously wrote inventory adjustments per productId/variantId from a
  /// multi-size scan. This is architecturally incorrect because the ESP32-CAM
  /// cannot determine honey variety from bottle size alone.
  ///
  /// Replaced by [acknowledgeScanWithMismatches] + manual Stock Corrections.
  @Deprecated(
    'ESP32 size discrepancies cannot be reconciled to a specific product. '
    'Use acknowledgeScanWithMismatches() then direct the admin to Stock Corrections.',
  )
  Future<void> reconcileScanSizes({
    required String scanId,
    required List<Map<String, dynamic>> mismatches,
    required String adminId,
    required String adminName,
  }) async {
    // Removed: inventory writes (they were architecturally incorrect).
    // The mismatches list may contain productId/variantId from old scan records,
    // but using them here would falsely attribute a size-level discrepancy
    // to a specific honey variety, which the camera cannot determine.

    // Only acknowledge the scan — no inventory change.
    await acknowledgeScanWithMismatches(
      scanId: scanId,
      adminId: adminId,
      adminName: adminName,
    );
  }
}
