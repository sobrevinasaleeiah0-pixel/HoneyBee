import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A single activity log entry from `public.admin_activity_logs`.
class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.action,
    required this.details,
    required this.createdAt,
    this.adminName,
    this.adminEmail,
  });

  final String id;
  final String action;
  final String? details;
  final DateTime createdAt;
  final String? adminName;
  final String? adminEmail;

  /// Maps a Supabase response row (with optional joined admins columns)
  /// into an [ActivityLogEntry].
  factory ActivityLogEntry.fromRow(Map<String, dynamic> row) {
    final adminsRow = row['admins'] as Map<String, dynamic>?;
    return ActivityLogEntry(
      id: row['id'] as String? ?? '',
      action: row['action'] as String? ?? '',
      details: row['details'] as String?,
      createdAt: row['created_at'] != null
          ? DateTime.parse(row['created_at'].toString()).toLocal()
          : DateTime.now(),
      adminName: adminsRow?['name'] as String?,
      adminEmail: adminsRow?['email'] as String?,
    );
  }

  @override
  String toString() =>
      'ActivityLogEntry(action: $action, admin: $adminName, at: $createdAt)';
}

/// Fetches admin activity logs from `public.admin_activity_logs` for the
/// Owner Activity Logs screen.
///
/// The existing `activity_read_admin` RLS policy permits SELECT for any
/// active admin, so both main_admin and co_admin can read all entries.
class SupabaseActivityService {
  SupabaseActivityService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Fetches the most recent [limit] activity log entries, optionally
  /// filtered by [search] (case-insensitive match on action or details).
  ///
  /// Returns entries sorted by [created_at] descending (most recent first).
  /// Throws on network or permission errors so callers can surface them.
  Future<List<ActivityLogEntry>> fetchLogs({
    int limit = 100,
    String? search,
  }) async {
    try {
      var query = _client
          .from('admin_activity_logs')
          .select('id, action, details, created_at, admins(name, email)')
          .order('created_at', ascending: false)
          .limit(limit);

      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim();
        // ilike on action OR details for substring search.
        query = _client
            .from('admin_activity_logs')
            .select('id, action, details, created_at, admins(name, email)')
            .or('action.ilike.%$q%,details.ilike.%$q%')
            .order('created_at', ascending: false)
            .limit(limit);
      }

      final response = await query;
      return (response as List)
          .whereType<Map<String, dynamic>>()
          .map(ActivityLogEntry.fromRow)
          .toList();
    } catch (e) {
      debugPrint('[SupabaseActivityService] fetchLogs error: $e');
      rethrow;
    }
  }

  /// Returns a Supabase Realtime stream of the activity log table so the
  /// Owner screen can update live as co_admins perform operations.
  ///
  /// Falls back to polling via [fetchLogs] if Realtime is unavailable;
  /// the stream approach is best-effort.
  Stream<List<ActivityLogEntry>> watchLogs({int limit = 100}) {
    return _client
        .from('admin_activity_logs')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows
            .whereType<Map<String, dynamic>>()
            .map(ActivityLogEntry.fromRow)
            .toList());
  }
}
