/// Administrator status service — production entry point.
///
/// Exports all pure types from [admin_status_interfaces.dart] and adds
/// SDK-backed production implementations plus the production factory.
library;

import 'package:firebase_database/firebase_database.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_status_interfaces.dart';

export 'admin_status_interfaces.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Production backend implementations (SDK-dependent)
// ─────────────────────────────────────────────────────────────────────────────

class _SupabaseAdminsBackend implements AdminSupabaseBackend {
  _SupabaseAdminsBackend(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> findCoAdminByEmail(String email) async {
    final result = await _client
        .from('admins')
        .select('id, role, status, email')
        .ilike('email', email)
        .eq('role', 'co_admin');
    return (result as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> updateStatusByEmail(
    String email,
    String newStatus,
  ) async {
    final result = await _client
        .from('admins')
        .update({'status': newStatus})
        .ilike('email', email)
        .eq('role', 'co_admin')
        .select('id, email, status, role');
    return (result as List).cast<Map<String, dynamic>>();
  }
}

class _FirebaseAdminsBackend implements AdminFirebaseBackend {
  @override
  Future<void> updateAdminStatus(String adminId, String newStatus) async {
    await FirebaseDatabase.instance.ref().child('admins').child(adminId).update(
      {'status': newStatus, 'isActive': newStatus == 'active'},
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Production factory extension
// ─────────────────────────────────────────────────────────────────────────────

/// Extends [AdminStatusService] with a production factory that wires the
/// live Supabase and Firebase SDK backends.
extension AdminStatusServiceProduction on AdminStatusService {
  /// Creates a production instance backed by the live Supabase and Firebase
  /// clients. Always call this in application code.
  static AdminStatusService create() {
    return AdminStatusService(
      supabaseBackend: _SupabaseAdminsBackend(Supabase.instance.client),
      firebaseBackend: _FirebaseAdminsBackend(),
    );
  }
}
