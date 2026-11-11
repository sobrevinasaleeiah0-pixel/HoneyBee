import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseNotificationService {
  SupabaseNotificationService._();

  static final SupabaseNotificationService instance =
      SupabaseNotificationService._();

  SupabaseClient get _client => Supabase.instance.client;

  final BehaviorSubject<List<Map<String, dynamic>>> _notifications =
      BehaviorSubject<List<Map<String, dynamic>>>.seeded(
        <Map<String, dynamic>>[],
      );
  Timer? _fallbackRefreshTimer;
  bool _started = false;

  Stream<List<Map<String, dynamic>>> get notificationsStream {
    _start();
    return _notifications.stream;
  }

  static List<Map<String, dynamic>> mapRows(List<dynamic> rows) =>
      rows.whereType<Map>().map((row) {
        final item = Map<String, dynamic>.from(row);
        final createdAt = DateTime.tryParse(
          item['created_at']?.toString() ?? '',
        );
        return <String, dynamic>{
          'id': item['id']?.toString() ?? '',
          'type': item['type']?.toString() ?? '',
          'message': item['message']?.toString() ?? '',
          'relatedId': item['related_id']?.toString(),
          'isRead': item['is_read'] == true,
          'isArchived': item['is_archived'] == true,
          'timestamp': createdAt?.millisecondsSinceEpoch ?? 0,
        };
      }).toList();

  void _start() {
    if (_started) return;
    _started = true;

    _client
        .channel('admin-notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          callback: (_) => _refreshFromRealtime(),
        )
        .subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.channelError ||
              status == RealtimeSubscribeStatus.timedOut ||
              status == RealtimeSubscribeStatus.closed) {
            final failure = error ?? 'Realtime notification updates failed';
            debugPrint(
              '[SupabaseNotificationService] Live updates unavailable; '
              'using periodic refresh: $failure',
            );
            _startFallbackRefresh();
          } else if (status == RealtimeSubscribeStatus.subscribed) {
            _fallbackRefreshTimer?.cancel();
            _fallbackRefreshTimer = null;
          }
        });

    _refreshFromRealtime();
  }

  void _startFallbackRefresh() {
    _fallbackRefreshTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshFromRealtime(),
    );
    _refreshFromRealtime();
  }

  Future<void> _refreshFromRealtime() async {
    try {
      await refresh();
    } catch (_) {
      // refresh logs failures and emits them to the notification stream.
    }
  }

  Future<void> refresh() async {
    try {
      final rows = await _client
          .from('notifications')
          .select(
            'id, type, message, related_id, is_read, is_archived, created_at',
          )
          .order('created_at', ascending: false);

      _notifications.add(mapRows(rows as List));
    } catch (error, stackTrace) {
      debugPrint(
        '[SupabaseNotificationService] Failed to load notifications: $error',
      );
      _notifications.addError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> markAsRead(String id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
    await refresh();
  }

  Future<void> markAllAsRead() async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('is_read', false);
    await refresh();
  }

  Future<void> setArchived(String id, bool archived) async {
    await _client
        .from('notifications')
        .update({'is_archived': archived})
        .eq('id', id);
    await refresh();
  }

  Future<void> createFromAdmin({
    required String type,
    required String message,
    String? relatedId,
  }) async {
    await _client.rpc(
      'create_admin_notification',
      params: {'p_type': type, 'p_message': message, 'p_related_id': relatedId},
    );
    await refresh();
  }
}
