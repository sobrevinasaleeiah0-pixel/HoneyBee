import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FirestoreService
//
// Handles real-time data synchronization with the Mobile App via Cloud Firestore.
// Mobile App uses Firestore for orders and products.
// Website listens to Firestore for real-time order updates.
// ─────────────────────────────────────────────────────────────────────────────

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Orders from Mobile App ────────────────────────────────────────────────

  /// Real-time stream of orders from the mobile app's Firestore orders collection
  Stream<QuerySnapshot> getOrdersStream() {
    return _firestore
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Get a single order by orderId
  Future<DocumentSnapshot?> getOrderById(String orderId) async {
    try {
      final doc = await _firestore.collection('orders').doc(orderId).get();
      return doc.exists ? doc : null;
    } catch (e) {
      return null;
    }
  }

  /// Update order status (called from website to update mobile app)
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _firestore.collection('orders').doc(orderId).update({
      'orderStatus': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update payment verification status
  Future<void> updatePaymentVerification(
    String orderId,
    String verificationStatus,
  ) async {
    await _firestore.collection('orders').doc(orderId).update({
      'paymentVerificationStatus': verificationStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Products (Read from Firestore for Mobile App) ────────────────────────

  /// Real-time stream of products from Firestore
  Stream<QuerySnapshot> getProductsStream() {
    return _firestore
        .collection('products')
        .where('isAvailable', isEqualTo: true)
        .orderBy('name')
        .snapshots();
  }

  /// Add/update product in Firestore (syncs to mobile app)
  Future<void> syncProduct(Map<String, dynamic> productData) async {
    final productId = productData['id'] as String?;
    if (productId == null) return;

    await _firestore.collection('products').doc(productId).set({
      ...productData,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Archive product in Firestore
  Future<void> archiveProduct(String productId, bool archive) async {
    await _firestore.collection('products').doc(productId).update({
      'isAvailable': !archive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Helper: Map Firestore Document to Order Model ───────────────────────

  /// Converts Firestore document to a consistent order map structure
  /// This bridges the mobile app's Firestore structure with the website's expected format
  static Map<String, dynamic> mapFirestoreOrder(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) return {};

    // Map Firestore fields to website-compatible structure
    return {
      'orderId': data['orderId'] ?? doc.id,
      'totalPrice': data['totalPrice'] ?? 0.0,
      'paymentMethod': data['paymentMethod'] ?? '',
      'paymentName': data['paymentName'] ?? '',
      'orderStatus': data['orderStatus'] ?? 'pending',
      'statusName': data['statusName'] ?? data['orderStatus'] ?? 'Pending',
      'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
      'paymentVerificationStatus': data['paymentVerificationStatus'] ?? 'notSubmitted',
      'paymentProofPath': data['paymentProofPath'] ?? '',
      'paymentReference': data['paymentReference'] ?? '',
      'paymentAmount': data['paymentAmount'] ?? 0.0,
      'items': data['items'] ?? [],
      'customerName': data['customerName'] ?? '',
      'customerPhone': data['customerPhone'] ?? '',
      'customerEmail': data['customerEmail'] ?? '',
      'customerAddress': data['customerAddress'] ?? '',
      // Add any additional fields needed by the website
      'firebaseDocId': doc.id,
    };
  }

  /// Converts Firestore document to product map structure
  static Map<String, dynamic> mapFirestoreProduct(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;

    if (data == null) return {};

    return {
      'id': doc.id,
      'name': data['name'] ?? '',
      'category': data['category'] ?? '',
      'weight': data['weight'] ?? '',
      'price': data['price'] ?? 0.0,
      'stock': data['stock'] ?? 0,
      'imageUrl': data['imageUrl'] ?? data['imagePath'] ?? '',
      'isAvailable': data['isAvailable'] ?? true,
      'isBestSeller': data['isBestSeller'] ?? false,
      'firebaseDocId': doc.id,
    };
  }
}
