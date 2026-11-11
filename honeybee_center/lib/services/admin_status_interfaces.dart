import 'dart:developer' as dev;

/// Pure-Dart interfaces, result types, and the core [AdminStatusService]
/// logic for administrator status management.
///
/// This file has NO dependency on Firebase or Supabase SDKs, making it
/// safe to import in unit tests without platform initialization.
///
/// Production code should import [admin_status_service.dart], which re-exports
/// everything here and additionally provides the concrete SDK-backed
/// implementations plus the [AdminStatusService.production()] factory.

// ─────────────────────────────────────────────────────────────────────────────
// Injectable backend interfaces
// ─────────────────────────────────────────────────────────────────────────────

/// Supabase operations required by [AdminStatusService].
/// Production: `_SupabaseAdminsBackend` in admin_status_service.dart.
/// Tests: a pure-Dart fake that implements this interface.
abstract class AdminSupabaseBackend {
  /// Returns co_admin rows matching [email] (case-insensitive).
  /// Must filter `role = 'co_admin'` — never returns main_admin rows.
  Future<List<Map<String, dynamic>>> findCoAdminByEmail(String email);

  /// Updates `admins.status` for co_admin rows matching [email].
  /// Returns the updated rows so the caller can verify exactly one row changed.
  Future<List<Map<String, dynamic>>> updateStatusByEmail(
    String email,
    String newStatus,
  );
}

/// Firebase operations required by [AdminStatusService].
/// Production: `_FirebaseAdminsBackend` in admin_status_service.dart.
/// Tests: a pure-Dart fake that implements this interface.
abstract class AdminFirebaseBackend {
  /// Updates `admins/{adminId}.{status, isActive}` in Firebase RTDB.
  Future<void> updateAdminStatus(String adminId, String newStatus);
}

// ─────────────────────────────────────────────────────────────────────────────
// Result type
// ─────────────────────────────────────────────────────────────────────────────

/// Result of an administrator status update operation.
///
/// Supabase is always updated first (single source of truth for login).
/// Firebase is synchronised afterwards as a secondary display mirror.
/// A partial failure is surfaced so the caller can retry Firebase sync
/// without re-running the authoritative Supabase update.
class AdminStatusUpdateResult {
  AdminStatusUpdateResult._({
    required this.supabaseUpdated,
    required this.firebaseUpdated,
    this.errorMessage,
    this.firebaseErrorMessage,
    this.firebaseAdminId,
  });

  /// Both Supabase and Firebase updated successfully.
  factory AdminStatusUpdateResult.fullSuccess() =>
      AdminStatusUpdateResult._(supabaseUpdated: true, firebaseUpdated: true);

  /// Supabase updated; Firebase sync failed — partial failure for retry.
  factory AdminStatusUpdateResult.partialFailure({
    required String firebaseError,
    required String firebaseAdminId,
  }) => AdminStatusUpdateResult._(
    supabaseUpdated: true,
    firebaseUpdated: false,
    firebaseErrorMessage: firebaseError,
    firebaseAdminId: firebaseAdminId,
  );

  /// The operation failed entirely (Supabase was not modified).
  factory AdminStatusUpdateResult.failure(String message) =>
      AdminStatusUpdateResult._(
        supabaseUpdated: false,
        firebaseUpdated: false,
        errorMessage: message,
      );

  /// Supabase `public.admins.status` was updated successfully.
  final bool supabaseUpdated;

  /// Firebase `admins/{id}` mirror was also updated.
  final bool firebaseUpdated;

  /// Set when the operation failed (Supabase was not modified).
  final String? errorMessage;

  /// Set when Supabase succeeded but Firebase sync failed.
  /// Use [AdminStatusService.retryFirebaseSync] with [firebaseAdminId].
  final String? firebaseErrorMessage;

  /// Firebase push-key for the admin record — used for retry.
  final String? firebaseAdminId;

  /// True when Supabase was updated (login is already enforced correctly).
  bool get success => supabaseUpdated;

  /// True when Supabase succeeded but Firebase mirror did not.
  bool get isPartialFailure => supabaseUpdated && !firebaseUpdated;

  @override
  String toString() =>
      'AdminStatusUpdateResult('
      'supabase: $supabaseUpdated, '
      'firebase: $firebaseUpdated, '
      'error: $errorMessage, '
      'fbError: $firebaseErrorMessage)';
}

// ─────────────────────────────────────────────────────────────────────────────
// AdminStatusService — SDK-independent core logic
// ─────────────────────────────────────────────────────────────────────────────

/// Manages administrator status updates with Supabase as the single source
/// of truth.
///
/// Update sequence (per approval):
///   1. Validate: email must belong to a co_admin row — never main_admin.
///   2. Update Supabase `public.admins.status` first (authoritative).
///   3. Verify exactly one co_admin row was modified with the correct status.
///   4. Synchronise Firebase mirror only after Supabase succeeds.
///   5. If Firebase sync fails, surface the partial failure for retry.
///
/// No SQL migrations, no RLS changes, no account creation or deletion.
/// Existing RLS `admins_update` already permits main_admin to update
/// co_admin rows — no policy change needed.
///
/// The production [AdminStatusService.production()] factory is available
/// in `admin_status_service.dart`, which re-exports this class.
class AdminStatusService {
  static const Duration _firebaseSyncTimeout = Duration(seconds: 8);

  AdminStatusService({
    required AdminSupabaseBackend supabaseBackend,
    required AdminFirebaseBackend firebaseBackend,
  }) : _supabase = supabaseBackend,
       _firebase = firebaseBackend;

  final AdminSupabaseBackend _supabase;
  final AdminFirebaseBackend _firebase;

  /// Updates the administrator status for a co_admin account.
  ///
  /// [adminEmail]      — email matched case-insensitively; must be co_admin.
  /// [adminFirebaseId] — Firebase RTDB push key (secondary mirror only).
  /// [newStatus]       — `'active'` or `'inactive'`.
  /// [performerName]   — display name of the acting admin (informational).
  Future<AdminStatusUpdateResult> updateCoAdminStatus({
    required String adminEmail,
    required String adminFirebaseId,
    required String newStatus,
    String? performerName,
  }) async {
    assert(
      newStatus == 'active' || newStatus == 'inactive',
      'newStatus must be "active" or "inactive"',
    );

    final email = adminEmail.trim().toLowerCase();
    if (email.isEmpty) {
      return AdminStatusUpdateResult.failure('Email must not be empty.');
    }

    // ── Step 1: Verify target is a co_admin row — never touch main_admin ──────
    List<Map<String, dynamic>> existing;
    try {
      existing = await _supabase.findCoAdminByEmail(email);
    } catch (e) {
      dev.log('[AdminStatusService] Pre-check failed: $e');
      return AdminStatusUpdateResult.failure(
        'Could not verify admin record: $e',
      );
    }

    if (existing.isEmpty) {
      return AdminStatusUpdateResult.failure(
        'No active co_admin record found for "$adminEmail". '
        'Supabase was not modified.',
      );
    }
    if (existing.length > 1) {
      return AdminStatusUpdateResult.failure(
        'Unexpected: multiple co_admin records match "$adminEmail". '
        'Supabase was not modified.',
      );
    }

    // Extra guard: pre-check filtered for co_admin; be explicit.
    if (existing.first['role'] == 'main_admin') {
      return AdminStatusUpdateResult.failure(
        'Owner (main_admin) status must not be changed.',
      );
    }

    // ── Step 2: Update Supabase (authoritative) ────────────────────────────────
    List<Map<String, dynamic>> updated;
    try {
      updated = await _supabase.updateStatusByEmail(email, newStatus);
    } catch (e) {
      dev.log('[AdminStatusService] Supabase update failed: $e');
      return AdminStatusUpdateResult.failure('Supabase update failed: $e');
    }

    if (updated.isEmpty) {
      return AdminStatusUpdateResult.failure(
        'Supabase update returned no rows for "$adminEmail". '
        'The record may have been removed or the caller lacks permission.',
      );
    }
    if (updated.length > 1) {
      return AdminStatusUpdateResult.failure(
        'Unexpected: Supabase updated ${updated.length} rows for '
        '"$adminEmail". Expected exactly 1. No Firebase sync attempted.',
      );
    }

    final returnedStatus = updated.first['status'] as String? ?? '';
    if (returnedStatus != newStatus) {
      return AdminStatusUpdateResult.failure(
        'Supabase returned status "$returnedStatus" instead of '
        '"$newStatus". Update may not have applied.',
      );
    }

    dev.log(
      '[AdminStatusService] Supabase admins.status updated: '
      '$adminEmail → $newStatus',
    );

    // ── Step 3: Synchronise Firebase mirror (secondary) ────────────────────────
    // Firebase is a display mirror only; Supabase governs login.
    try {
      await _firebase
          .updateAdminStatus(adminFirebaseId, newStatus)
          .timeout(_firebaseSyncTimeout);
    } catch (e) {
      dev.log('[AdminStatusService] Firebase sync failed: $e');
      return AdminStatusUpdateResult.partialFailure(
        firebaseError:
            'Supabase update succeeded but Firebase mirror sync failed: $e. '
            'Login is governed by Supabase — the user is already '
            '${newStatus == 'active' ? 'active' : 'blocked'}. '
            'Use retryFirebaseSync() to resolve the display inconsistency.',
        firebaseAdminId: adminFirebaseId,
      );
    }

    dev.log(
      '[AdminStatusService] Firebase mirror synced: '
      '$adminFirebaseId → $newStatus',
    );

    return AdminStatusUpdateResult.fullSuccess();
  }

  /// Retries the Firebase mirror sync after a partial failure.
  ///
  /// Call with [firebaseAdminId] and [newStatus] from a previous
  /// [AdminStatusUpdateResult] where [isPartialFailure] is `true`.
  Future<bool> retryFirebaseSync({
    required String firebaseAdminId,
    required String newStatus,
  }) async {
    assert(
      newStatus == 'active' || newStatus == 'inactive',
      'newStatus must be "active" or "inactive"',
    );
    try {
      await _firebase
          .updateAdminStatus(firebaseAdminId, newStatus)
          .timeout(_firebaseSyncTimeout);
      dev.log(
        '[AdminStatusService] Firebase retry succeeded: $firebaseAdminId',
      );
      return true;
    } catch (e) {
      dev.log('[AdminStatusService] Firebase retry failed: $e');
      return false;
    }
  }
}
