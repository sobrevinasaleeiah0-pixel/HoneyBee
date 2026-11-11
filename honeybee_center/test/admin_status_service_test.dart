import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/services/admin_status_interfaces.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminStatusService — unit tests
//
// Because AdminStatusService accepts injected [AdminSupabaseBackend] and
// [AdminFirebaseBackend] interfaces, we use pure-Dart fakes that simulate
// the relevant behavior without any real database, account, or network call.
//
// Scenarios covered:
//   1.  Successful deactivation (Supabase + Firebase both succeed).
//   2.  Successful activation.
//   3.  Missing co_admin record → Supabase not modified.
//   4.  Owner (main_admin) protection — email query returns no co_admin row.
//   5.  Explicit main_admin guard in the returned row.
//   6.  Empty/whitespace email → rejected immediately.
//   7.  Partial failure — Supabase ok, Firebase throws.
//   8.  retryFirebaseSync resolves a partial failure.
//   9.  retryFirebaseSync returns false when Firebase still fails.
//   10. Supabase pre-check throws.
//   11. Supabase update throws.
//   12. Supabase returns wrong status.
//   13. Supabase update returns multiple rows.
//   14. AdminStatusUpdateResult flag semantics.
// ─────────────────────────────────────────────────────────────────────────────

// ── Fake Supabase backend ──────────────────────────────────────────────────────

class _FakeSupabaseBackend implements AdminSupabaseBackend {
  _FakeSupabaseBackend({
    required this.findRows,
    required this.updateRows,
    this.findThrows = false,
    this.updateThrows = false,
  });

  final List<Map<String, dynamic>> findRows;
  final List<Map<String, dynamic>> updateRows;
  final bool findThrows;
  final bool updateThrows;

  String? lastUpdatedEmail;
  String? lastUpdatedStatus;

  @override
  Future<List<Map<String, dynamic>>> findCoAdminByEmail(String email) async {
    if (findThrows) throw Exception('Simulated Supabase select error');
    return findRows;
  }

  @override
  Future<List<Map<String, dynamic>>> updateStatusByEmail(
    String email,
    String newStatus,
  ) async {
    if (updateThrows) throw Exception('Simulated Supabase update error');
    lastUpdatedEmail = email;
    lastUpdatedStatus = newStatus;
    return updateRows;
  }
}

// ── Fake Firebase backend ─────────────────────────────────────────────────────

class _FakeFirebaseBackend implements AdminFirebaseBackend {
  _FakeFirebaseBackend({this.shouldThrow = false});

  final bool shouldThrow;
  bool updateWasCalled = false;
  String? lastAdminId;
  String? lastStatus;

  @override
  Future<void> updateAdminStatus(String adminId, String newStatus) async {
    if (shouldThrow) throw Exception('Simulated Firebase error');
    updateWasCalled = true;
    lastAdminId = adminId;
    lastStatus = newStatus;
  }
}

// ── Helper ─────────────────────────────────────────────────────────────────────

AdminStatusService makeService({
  List<Map<String, dynamic>> findRows = const [],
  List<Map<String, dynamic>> updateRows = const [],
  bool supabaseFindThrows = false,
  bool supabaseUpdateThrows = false,
  bool firebaseThrows = false,
}) {
  return AdminStatusService(
    supabaseBackend: _FakeSupabaseBackend(
      findRows: findRows,
      updateRows: updateRows,
      findThrows: supabaseFindThrows,
      updateThrows: supabaseUpdateThrows,
    ),
    firebaseBackend: _FakeFirebaseBackend(shouldThrow: firebaseThrows),
  );
}

const _coAdminActive = {
  'id': 'uuid-co',
  'role': 'co_admin',
  'status': 'active',
  'email': 'coadmin67@gmail.com',
};

const _coAdminInactiveResult = {
  'id': 'uuid-co',
  'email': 'coadmin67@gmail.com',
  'status': 'inactive',
  'role': 'co_admin',
};

const _coAdminActiveResult = {
  'id': 'uuid-co',
  'email': 'coadmin67@gmail.com',
  'status': 'active',
  'role': 'co_admin',
};

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  group('AdminStatusService.updateCoAdminStatus', () {
    // ── 1. Successful deactivation ─────────────────────────────────────────
    test('returns full success when both Supabase and Firebase succeed', () async {
      final svc = makeService(
        findRows: [_coAdminActive],
        updateRows: [_coAdminInactiveResult],
      );

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'coadmin67@gmail.com',
        adminFirebaseId: 'fb-key-123',
        newStatus: 'inactive',
        performerName: 'System Owner',
      );

      expect(result.success, isTrue);
      expect(result.supabaseUpdated, isTrue);
      expect(result.firebaseUpdated, isTrue);
      expect(result.isPartialFailure, isFalse);
      expect(result.errorMessage, isNull);
    });

    // ── 2. Successful activation ───────────────────────────────────────────
    test('can activate a previously inactive co_admin', () async {
      final svc = makeService(
        findRows: [
          {'id': 'uuid-co', 'role': 'co_admin', 'status': 'inactive',
           'email': 'coadmin67@gmail.com'},
        ],
        updateRows: [_coAdminActiveResult],
      );

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'coadmin67@gmail.com',
        adminFirebaseId: 'fb-key-123',
        newStatus: 'active',
      );

      expect(result.success, isTrue);
      expect(result.firebaseUpdated, isTrue);
    });

    // ── 3. Missing co_admin record ─────────────────────────────────────────
    test('rejects when no co_admin row matches the email', () async {
      final svc = makeService(findRows: [], updateRows: []);

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'nobody@example.com',
        adminFirebaseId: 'fb-key-999',
        newStatus: 'inactive',
      );

      expect(result.success, isFalse);
      expect(result.firebaseUpdated, isFalse);
      expect(result.errorMessage, contains('No active co_admin record found'));
    });

    // ── 4. Owner protection — email resolves to no co_admin row ───────────
    // The findCoAdminByEmail query filters `role = 'co_admin'`, so the
    // owner's row (main_admin) would return empty — simulated here.
    test('rejects update when the email belongs to an owner (main_admin) account', () async {
      // The .eq('role','co_admin') filter means a main_admin email returns empty.
      final svc = makeService(findRows: [], updateRows: []);

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'owner@honeybee.com',
        adminFirebaseId: 'owner-fb-key',
        newStatus: 'inactive',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('No active co_admin record found'));
    });

    // ── 5. Explicit main_admin guard on returned row ───────────────────────
    // Defence-in-depth: even if a main_admin row somehow slips through the
    // query filter, the service must explicitly reject it.
    test('rejects if a main_admin row is returned by the find query', () async {
      final svc = makeService(
        findRows: [
          {'id': 'uuid-owner', 'role': 'main_admin', 'status': 'active',
           'email': 'owner@honeybee.com'},
        ],
        updateRows: [],
      );

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'owner@honeybee.com',
        adminFirebaseId: 'owner-fb-key',
        newStatus: 'inactive',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('main_admin'));
    });

    // ── 6. Empty email ─────────────────────────────────────────────────────
    test('rejects immediately when email is empty', () async {
      final svc = makeService();

      final result = await svc.updateCoAdminStatus(
        adminEmail: '   ',
        adminFirebaseId: 'fb-key',
        newStatus: 'inactive',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Email must not be empty'));
    });

    // ── 7. Partial failure — Supabase succeeds, Firebase throws ───────────
    test('reports partial failure when Firebase sync fails after Supabase success', () async {
      final svc = makeService(
        findRows: [_coAdminActive],
        updateRows: [_coAdminInactiveResult],
        firebaseThrows: true,
      );

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'coadmin67@gmail.com',
        adminFirebaseId: 'fb-key-123',
        newStatus: 'inactive',
      );

      // Supabase is authoritative — login is already blocked.
      expect(result.supabaseUpdated, isTrue);
      expect(result.firebaseUpdated, isFalse);
      expect(result.isPartialFailure, isTrue);
      // Retry metadata is present.
      expect(result.firebaseAdminId, equals('fb-key-123'));
      expect(result.firebaseErrorMessage, isNotNull);
      expect(result.firebaseErrorMessage, contains('Firebase mirror sync failed'));
      // The update is considered a success (Supabase governs login).
      expect(result.success, isTrue);
    });

    // ── 10. Supabase pre-check throws ──────────────────────────────────────
    test('returns failure when Supabase pre-check throws', () async {
      final svc = makeService(supabaseFindThrows: true);

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'coadmin67@gmail.com',
        adminFirebaseId: 'fb-key-123',
        newStatus: 'inactive',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Could not verify admin record'));
    });

    // ── 11. Supabase update throws ─────────────────────────────────────────
    test('returns failure when Supabase update throws', () async {
      final svc = makeService(
        findRows: [_coAdminActive],
        supabaseUpdateThrows: true,
      );

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'coadmin67@gmail.com',
        adminFirebaseId: 'fb-key-123',
        newStatus: 'inactive',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Supabase update failed'));
    });

    // ── 12. Supabase returns wrong status ──────────────────────────────────
    test('returns failure when Supabase echoes back the wrong status', () async {
      // Supabase echoes 'active' instead of the requested 'inactive'.
      final svc = makeService(
        findRows: [_coAdminActive],
        updateRows: [_coAdminActiveResult], // wrong — should be 'inactive'
      );

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'coadmin67@gmail.com',
        adminFirebaseId: 'fb-key-123',
        newStatus: 'inactive',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('returned status'));
    });

    // ── 13. Supabase returns multiple rows ─────────────────────────────────
    test('returns failure when Supabase update affects multiple rows', () async {
      final svc = makeService(
        findRows: [_coAdminActive],
        updateRows: [
          _coAdminInactiveResult,
          {'id': 'uuid-co2', 'email': 'other@gmail.com',
           'status': 'inactive', 'role': 'co_admin'},
        ],
      );

      final result = await svc.updateCoAdminStatus(
        adminEmail: 'coadmin67@gmail.com',
        adminFirebaseId: 'fb-key-123',
        newStatus: 'inactive',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('updated'));
    });

    // ── Verifies Supabase email/status args are passed correctly ───────────
    test('passes lowercased email and correct newStatus to backend', () async {
      final fakeSupabase = _FakeSupabaseBackend(
        findRows: [_coAdminActive],
        updateRows: [_coAdminInactiveResult],
      );
      final svc = AdminStatusService(
        supabaseBackend: fakeSupabase,
        firebaseBackend: _FakeFirebaseBackend(),
      );

      await svc.updateCoAdminStatus(
        adminEmail: 'CoAdmin67@GMAIL.COM',
        adminFirebaseId: 'fb-key-123',
        newStatus: 'inactive',
      );

      expect(fakeSupabase.lastUpdatedEmail, equals('coadmin67@gmail.com'));
      expect(fakeSupabase.lastUpdatedStatus, equals('inactive'));
    });

    // ── Verifies Firebase receives correct args ────────────────────────────
    test('passes correct adminId and status to Firebase backend', () async {
      final fakeFirebase = _FakeFirebaseBackend();
      final svc = AdminStatusService(
        supabaseBackend: _FakeSupabaseBackend(
          findRows: [_coAdminActive],
          updateRows: [_coAdminInactiveResult],
        ),
        firebaseBackend: fakeFirebase,
      );

      await svc.updateCoAdminStatus(
        adminEmail: 'coadmin67@gmail.com',
        adminFirebaseId: 'fb-key-abc',
        newStatus: 'inactive',
      );

      expect(fakeFirebase.updateWasCalled, isTrue);
      expect(fakeFirebase.lastAdminId, equals('fb-key-abc'));
      expect(fakeFirebase.lastStatus, equals('inactive'));
    });
  });

  group('AdminStatusService.retryFirebaseSync', () {
    // ── 8. Retry succeeds ──────────────────────────────────────────────────
    test('returns true and calls Firebase when sync is available', () async {
      final fakeFirebase = _FakeFirebaseBackend();
      final svc = AdminStatusService(
        supabaseBackend: _FakeSupabaseBackend(findRows: [], updateRows: []),
        firebaseBackend: fakeFirebase,
      );

      final retried = await svc.retryFirebaseSync(
        firebaseAdminId: 'fb-key-123',
        newStatus: 'inactive',
      );

      expect(retried, isTrue);
      expect(fakeFirebase.updateWasCalled, isTrue);
      expect(fakeFirebase.lastAdminId, equals('fb-key-123'));
      expect(fakeFirebase.lastStatus, equals('inactive'));
    });

    // ── 9. Retry fails ─────────────────────────────────────────────────────
    test('returns false when Firebase is still unavailable', () async {
      final svc = AdminStatusService(
        supabaseBackend: _FakeSupabaseBackend(findRows: [], updateRows: []),
        firebaseBackend: _FakeFirebaseBackend(shouldThrow: true),
      );

      final retried = await svc.retryFirebaseSync(
        firebaseAdminId: 'fb-key-123',
        newStatus: 'inactive',
      );

      expect(retried, isFalse);
    });
  });

  group('AdminStatusUpdateResult flags', () {
    // ── 14a. Full success ──────────────────────────────────────────────────
    test('success + firebaseUpdated → not partial failure', () {
      final r = AdminStatusUpdateResult.fullSuccess();
      expect(r.success, isTrue);
      expect(r.isPartialFailure, isFalse);
    });

    // ── 14b. Partial failure ───────────────────────────────────────────────
    test('supabase ok + firebase failed → partial failure', () {
      final r = AdminStatusUpdateResult.partialFailure(
        firebaseError: 'network error',
        firebaseAdminId: 'fb-id',
      );
      expect(r.success, isTrue);
      expect(r.isPartialFailure, isTrue);
      expect(r.firebaseAdminId, equals('fb-id'));
    });

    // ── 14c. Both failed ───────────────────────────────────────────────────
    test('both failed → success=false, not partial failure', () {
      final r = AdminStatusUpdateResult.failure('no record found');
      expect(r.success, isFalse);
      expect(r.isPartialFailure, isFalse);
    });
  });
}
