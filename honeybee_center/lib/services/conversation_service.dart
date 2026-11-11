import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ConversationService {
  static const String imageBucket = 'customer-conversation-images';
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const Set<String> supportedImageTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchInbox() async {
    final result = await _client.rpc('get_admin_conversation_inbox');
    if (result is! List) {
      throw StateError('Supabase returned an invalid conversation inbox.');
    }
    final conversations = result
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final customerRows = await _client
        .from('customers')
        .select('id, name, email, phone, address')
        .eq('status', 'active')
        .not('auth_uid', 'is', null)
        .order('name');
    final customers = (customerRows as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    final customerIds = <String>{
      ...customers.map((customer) => customer['id'].toString()),
      ...conversations
          .map((conversation) => conversation['customer_id']?.toString())
          .whereType<String>(),
    }.toList();
    if (customerIds.isEmpty) return conversations;
    final orderRows = await _client
        .from('orders')
        .select(
          'id, customer_id, order_reference, order_status, payment_status, '
          'payment_method, payment_reference, payment_proof_url, payment_amount, '
          'total_amount, created_at, order_items(product_name, bottle_size, '
          'quantity, unit_price, subtotal)',
        )
        .inFilter('customer_id', customerIds)
        .order('created_at', ascending: false);
    final ordersByCustomer = <String, List<Map<String, dynamic>>>{};
    for (final row in (orderRows as List).whereType<Map>()) {
      final order = Map<String, dynamic>.from(row);
      final customerId = order['customer_id']?.toString();
      if (customerId == null) continue;
      ordersByCustomer.putIfAbsent(customerId, () => []).add({
        'id': order['id'],
        'reference': order['order_reference'],
        'status': order['order_status'],
        'payment_status': order['payment_status'],
        'payment_method': order['payment_method'],
        'payment_reference': order['payment_reference'],
        'payment_proof_url': order['payment_proof_url'],
        'payment_amount': order['payment_amount'],
        'total': order['total_amount'],
        'created_at': order['created_at'],
        'items': order['order_items'] ?? const [],
      });
    }

    return mergeInboxWithLinkedCustomers(
      conversations,
      customers,
      ordersByCustomer: ordersByCustomer,
    );
  }

  @visibleForTesting
  static List<Map<String, dynamic>> mergeInboxWithLinkedCustomers(
    List<Map<String, dynamic>> conversations,
    List<Map<String, dynamic>> customers, {
    Map<String, List<Map<String, dynamic>>> ordersByCustomer = const {},
  }) {
    final customersWithConversations = conversations
        .map((conversation) => conversation['customer_id']?.toString())
        .whereType<String>()
        .toSet();
    final result = conversations.map((conversation) {
      final customerId = conversation['customer_id']?.toString();
      final orders = ordersByCustomer[customerId];
      if (orders == null || orders.isEmpty) return conversation;

      final linkedOrderId = conversation['order_id']?.toString();
      Map<String, dynamic>? linkedOrder;
      for (final order in orders) {
        if (order['id']?.toString() == linkedOrderId) {
          linkedOrder = order;
          break;
        }
      }

      return <String, dynamic>{
        ...conversation,
        'customer_orders': orders,
        if (linkedOrder != null) ...{
          'order_status': linkedOrder['status'],
          'order_total': linkedOrder['total'],
          'payment_status': linkedOrder['payment_status'],
          'payment_method': linkedOrder['payment_method'],
          'payment_reference': linkedOrder['payment_reference'],
          'payment_proof_url': linkedOrder['payment_proof_url'],
          'payment_amount': linkedOrder['payment_amount'],
        },
      };
    }).toList();
    for (final customer in customers) {
      final customerId = customer['id']?.toString();
      if (customerId == null ||
          customersWithConversations.contains(customerId)) {
        continue;
      }
      result.add({
        'conversation_id': null,
        'customer_id': customerId,
        'customer_name': customer['name'],
        'customer_email': customer['email'],
        'customer_phone': customer['phone'],
        'customer_address': customer['address'],
        'customer_orders': ordersByCustomer[customerId] ?? const [],
        'order_id': null,
        'order_reference': null,
        'order_status': null,
        'order_total': null,
        'conversation_status': null,
        'last_message': null,
        'last_message_at': null,
        'last_sender_role': null,
        'last_attachment_path': null,
        'unread_count': 0,
      });
    }
    return result;
  }

  Stream<List<Map<String, dynamic>>> watchMessages(String conversationId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at');
  }

  Future<void> markRead(String conversationId) async {
    await _client.rpc(
      'mark_admin_conversation_read',
      params: {'p_conversation_id': conversationId},
    );
  }

  Future<void> setStatus(String conversationId, String status) async {
    if (status != 'open' && status != 'resolved') {
      throw ArgumentError.value(status, 'status');
    }
    await _client.rpc(
      'set_admin_conversation_status',
      params: {'p_conversation_id': conversationId, 'p_status': status},
    );
  }

  Future<void> sendText({
    required String conversationId,
    required String message,
  }) async {
    final text = message.trim();
    if (text.isEmpty) return;
    await _client.rpc(
      'send_admin_conversation_message',
      params: {
        'p_conversation_id': conversationId,
        'p_message': text,
        'p_attachment_path': null,
        'p_attachment_mime_type': null,
      },
    );
  }

  Future<void> sendImage({
    required String conversationId,
    required String adminUid,
    required XFile image,
    required String message,
  }) async {
    final mimeType = mimeTypeFor(image);
    final Uint8List bytes = await image.readAsBytes();
    validateImageUpload(mimeType: mimeType, byteLength: bytes.length);

    final path =
        'admin/$adminUid/$conversationId/${DateTime.now().microsecondsSinceEpoch}.${_extension(mimeType)}';
    await _client.storage
        .from(imageBucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: false),
        );

    try {
      await _client.rpc(
        'send_admin_conversation_message',
        params: {
          'p_conversation_id': conversationId,
          'p_message': message.trim(),
          'p_attachment_path': path,
          'p_attachment_mime_type': mimeType,
        },
      );
    } catch (error) {
      try {
        await _client.storage.from(imageBucket).remove([path]);
      } catch (cleanupError) {
        debugPrint(
          '[ConversationService] Attachment cleanup failed: $cleanupError',
        );
        throw StateError(
          'Message failed and its uploaded image could not be removed: $error',
        );
      }
      rethrow;
    }
  }

  Future<String> signedImageUrl(String path) {
    return _client.storage.from(imageBucket).createSignedUrl(path, 3600);
  }

  static String mimeTypeFor(XFile file) {
    final declaredType = file.mimeType?.toLowerCase();
    if (declaredType != null && supportedImageTypes.contains(declaredType)) {
      return declaredType;
    }

    switch (file.name.split('.').last.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return declaredType ?? '';
    }
  }

  static String validateImageUpload({
    required String mimeType,
    required int byteLength,
  }) {
    if (!supportedImageTypes.contains(mimeType)) {
      throw ArgumentError('Choose a JPEG, PNG, or WebP image.');
    }
    if (byteLength <= 0 || byteLength > maxImageBytes) {
      throw ArgumentError('Images must be smaller than 5 MB.');
    }
    return mimeType;
  }

  static String _extension(String mimeType) => switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => throw ArgumentError.value(mimeType, 'mimeType'),
  };
}
