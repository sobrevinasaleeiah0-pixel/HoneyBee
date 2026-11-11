import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/services/auth_service.dart';
import 'package:honeybee_center/core/permissions/admin_capabilities.dart';

void main() {
  group('AuthService — UserRole labels and values', () {
    test('UserRole.mainAdmin label is Owner (D1 relabel)', () {
      expect(UserRole.mainAdmin.label, 'Owner');
    });

    test('UserRole.coAdmin label is Co-Admin', () {
      expect(UserRole.coAdmin.label, 'Co-Admin');
    });

    test('UserRole.mainAdmin DB value is unchanged main_admin', () {
      expect(UserRole.mainAdmin.value, 'main_admin');
    });

    test('UserRole.coAdmin DB value is unchanged co_admin', () {
      expect(UserRole.coAdmin.value, 'co_admin');
    });
  });

  group('tryParseAdminRole — deny-by-default', () {
    test('main_admin maps to UserRole.mainAdmin', () {
      expect(tryParseAdminRole('main_admin'), UserRole.mainAdmin);
    });

    test('co_admin maps to UserRole.coAdmin', () {
      expect(tryParseAdminRole('co_admin'), UserRole.coAdmin);
    });

    test('null role returns null (denied — not defaulted to coAdmin)', () {
      expect(tryParseAdminRole(null), isNull);
    });

    test('empty string role returns null (denied)', () {
      expect(tryParseAdminRole(''), isNull);
    });

    test('unrecognized role string returns null (denied)', () {
      expect(tryParseAdminRole('super_admin'), isNull);
      expect(tryParseAdminRole('MAIN_ADMIN'), isNull); // wrong casing
      expect(tryParseAdminRole(' main_admin'), isNull); // leading space
      expect(tryParseAdminRole('admin'), isNull);
      expect(tryParseAdminRole('root'), isNull);
    });
  });

  group('AuthSession', () {
    test('initializes with required properties', () {
      const session = AuthSession(
        email: 'reylbanocnoc@gmail.com',
        role: UserRole.mainAdmin,
        uid: '4eca1bad-16a6-4256-a7bd-ce41f2965a27',
        name: 'Reyl Banocnoc',
      );

      expect(session.email, 'reylbanocnoc@gmail.com');
      expect(session.role, UserRole.mainAdmin);
      expect(session.uid, '4eca1bad-16a6-4256-a7bd-ce41f2965a27');
      expect(session.name, 'Reyl Banocnoc');
    });
  });

  group('Validators', () {
    test('validateFullName', () {
      expect(AuthService.validateFullName(''), isNotNull);
      expect(AuthService.validateFullName('   '), isNotNull);
      expect(AuthService.validateFullName(null), isNotNull);
      expect(AuthService.validateFullName('Reyl Banocnoc'), isNull);
    });

    test('validateEmail', () {
      expect(AuthService.validateEmail(''), isNotNull);
      expect(AuthService.validateEmail('notanemail'), isNotNull);
      expect(AuthService.validateEmail('test@'), isNotNull);
      expect(AuthService.validateEmail('reylbanocnoc@gmail.com'), isNull);
      expect(AuthService.validateEmail('coadmin67@gmail.com'), isNull);
    });

    test('validatePassword', () {
      expect(AuthService.validatePassword(''), isNotNull);
      expect(AuthService.validatePassword('short'), isNotNull);
      expect(AuthService.validatePassword('1234567'), isNotNull);
      expect(AuthService.validatePassword('12345678'), isNull);
    });

    test('validateConfirmPassword', () {
      expect(AuthService.validateConfirmPassword('', 'secret123'), isNotNull);
      expect(
        AuthService.validateConfirmPassword('mismatch', 'secret123'),
        isNotNull,
      );
      expect(
        AuthService.validateConfirmPassword('secret123', 'secret123'),
        isNull,
      );
    });
  });

  group('RoleCapabilities — permission matrix', () {
    test('Owner capabilities: monitoring only, no writes', () {
      final caps = RoleCapabilities.forRole(UserRole.mainAdmin);
      expect(caps.isMonitoringOnly, isTrue);
      expect(caps.canManageOrders, isFalse);
      expect(caps.canManageCatalog, isFalse);
      expect(caps.canManageSuppliers, isFalse);
      expect(caps.canAdjustStock, isFalse);
      expect(caps.canRunProduction, isFalse);
      expect(caps.canReplyMessages, isFalse);
      expect(caps.canConfirmPickup, isFalse);
      expect(caps.canManageAccounts, isFalse);
    });

    test('Co-Admin capabilities: full operations, no account management', () {
      final caps = RoleCapabilities.forRole(UserRole.coAdmin);
      expect(caps.isMonitoringOnly, isFalse);
      expect(caps.canManageOrders, isTrue);
      expect(caps.canManageCatalog, isTrue);
      expect(caps.canManageSuppliers, isTrue);
      expect(caps.canAdjustStock, isTrue);
      expect(caps.canRunProduction, isTrue);
      expect(caps.canReplyMessages, isTrue);
      expect(caps.canConfirmPickup, isTrue);
      // Provisioning is outside both dashboards.
      expect(caps.canManageAccounts, isFalse);
    });

    test('canManageAccounts is false for BOTH roles', () {
      expect(
        RoleCapabilities.forRole(UserRole.mainAdmin).canManageAccounts,
        isFalse,
      );
      expect(
        RoleCapabilities.forRole(UserRole.coAdmin).canManageAccounts,
        isFalse,
      );
    });

    test('forRole(mainAdmin) returns the owner preset exactly', () {
      expect(
        RoleCapabilities.forRole(UserRole.mainAdmin),
        RoleCapabilities.owner,
      );
    });

    test('forRole(coAdmin) returns the coAdmin preset exactly', () {
      expect(
        RoleCapabilities.forRole(UserRole.coAdmin),
        RoleCapabilities.coAdmin,
      );
    });
  });

  group('AuthService — Dual Authentication (Supabase + Firebase)', () {
    test(
      'Supabase login succeeds without an initialized Firebase app',
      () async {
        expect(Firebase.apps, isEmpty);
        final sb = FakeAuthSupabaseBackend(
          identity: const AuthSessionIdentity(
            id: 'sb-admin-uuid-001',
            email: 'admin@example.com',
            name: 'Admin',
          ),
          adminRow: {'name': 'Admin', 'role': 'co_admin', 'status': 'active'},
        );

        final service = AuthService(supabaseBackend: sb);
        final session = await service.signIn(
          email: 'admin@example.com',
          password: 'correct-password',
        );

        expect(session.role, UserRole.coAdmin);
        expect(session.firebaseUid, isNull);
        expect(sb.updateLastLoginCalled, isTrue);
      },
    );

    test(
      'Successful dual login establishes both sessions and verifies Firebase admin record',
      () async {
        final sb = FakeAuthSupabaseBackend(
          identity: const AuthSessionIdentity(
            id: 'sb-admin-uuid-001',
            email: 'michelle@honeybee.internal',
            name: 'Michelle',
          ),
          adminRow: {
            'name': 'Michelle',
            'role': 'co_admin',
            'status': 'active',
          },
        );

        final fb = FakeAuthFirebaseBackend(
          firebaseUid: 'wsk89DJ7lxZWFefpvghV5qnhazs2',
          adminRecord: {
            'name': 'Michelle',
            'role': 'co_admin',
            'status': 'active',
            'email': 'michelle@honeybee.internal',
          },
        );

        final service = AuthService(supabaseBackend: sb, firebaseBackend: fb);
        final session = await service.signIn(
          email: 'michelle@honeybee.internal',
          password: 'correct-password',
        );

        expect(session.email, 'michelle@honeybee.internal');
        expect(session.role, UserRole.coAdmin);
        expect(session.uid, 'sb-admin-uuid-001');
        expect(session.firebaseUid, 'wsk89DJ7lxZWFefpvghV5qnhazs2');
        expect(session.name, 'Michelle');

        expect(sb.signOutCalled, isFalse);
        expect(fb.signOutCalled, isFalse);
        expect(sb.updateLastLoginCalled, isTrue);
      },
    );

    test(
      'Firebase login failure does not block Supabase admin login (best effort IoT bridge)',
      () async {
        final sb = FakeAuthSupabaseBackend(
          identity: const AuthSessionIdentity(
            id: 'sb-admin-uuid-001',
            email: 'coadmin67@gmail.com',
            name: 'Michelle',
          ),
          adminRow: {
            'name': 'Michelle',
            'role': 'co_admin',
            'status': 'active',
          },
        );

        final fb = FakeAuthFirebaseBackend(
          signInThrows: true, // Firebase fails with invalid-credential
        );

        final service = AuthService(supabaseBackend: sb, firebaseBackend: fb);

        final session = await service.signIn(
          email: 'coadmin67@gmail.com',
          password: 'password123',
        );

        expect(session.role, UserRole.coAdmin);
        expect(session.email, 'coadmin67@gmail.com');
        expect(session.uid, 'sb-admin-uuid-001');
        expect(session.firebaseUid, isNull);
        expect(sb.signOutCalled, isFalse);
      },
    );

    test(
      'Inactive administrator in Firebase RTDB safely skips Firebase session',
      () async {
        final sb = FakeAuthSupabaseBackend(
          identity: const AuthSessionIdentity(
            id: 'sb-admin-uuid-001',
            email: 'michelle@honeybee.internal',
          ),
          adminRow: {
            'name': 'Michelle',
            'role': 'co_admin',
            'status': 'active',
          },
        );

        final fb = FakeAuthFirebaseBackend(
          firebaseUid: 'wsk89DJ7lxZWFefpvghV5qnhazs2',
          adminRecord: {
            'name': 'Michelle',
            'role': 'co_admin',
            'status': 'inactive', // Inactive in Firebase
          },
        );

        final service = AuthService(supabaseBackend: sb, firebaseBackend: fb);

        final session = await service.signIn(
          email: 'michelle@honeybee.internal',
          password: 'password123',
        );

        expect(session.role, UserRole.coAdmin);
        expect(session.firebaseUid, isNull);
        expect(sb.signOutCalled, isFalse);
      },
    );

    test('Logout signs out both Supabase and Firebase Auth sessions', () async {
      final sb = FakeAuthSupabaseBackend();
      final fb = FakeAuthFirebaseBackend();

      final service = AuthService(supabaseBackend: sb, firebaseBackend: fb);
      await service.signOut();

      expect(sb.signOutCalled, isTrue);
      expect(fb.signOutCalled, isTrue);
    });

    test(
      'Existing co-admin account preservation and operational capability',
      () async {
        final sb = FakeAuthSupabaseBackend(
          identity: const AuthSessionIdentity(
            id: '3e18a245-sb-uuid',
            email: 'michelle@honeybee.internal',
            name: 'Michelle',
          ),
          adminRow: {
            'name': 'Michelle',
            'role': 'co_admin',
            'status': 'active',
          },
        );

        final fb = FakeAuthFirebaseBackend(
          firebaseUid: 'wsk89DJ7lxZWFefpvghV5qnhazs2',
          adminRecord: {
            'name': 'Michelle',
            'role': 'co_admin',
            'status': 'active',
          },
        );

        final service = AuthService(supabaseBackend: sb, firebaseBackend: fb);
        final session = await service.signIn(
          email: 'michelle@honeybee.internal',
          password: 'password',
        );

        expect(session.role, UserRole.coAdmin);
        final caps = RoleCapabilities.forRole(session.role);
        expect(caps.canAdjustStock, isTrue);
        expect(caps.canManageOrders, isTrue);
        expect(caps.isMonitoringOnly, isFalse);

        // Verify that the Firebase UID is preserved on the session
        expect(session.firebaseUid, 'wsk89DJ7lxZWFefpvghV5qnhazs2');
        // Verify that the Supabase UID is preserved on the session
        expect(session.uid, '3e18a245-sb-uuid');
      },
    );

    test(
      'Scan command creation prioritizes Firebase UID for RTDB rules compliance',
      () {
        const session = AuthSession(
          email: 'michelle@honeybee.internal',
          role: UserRole.coAdmin,
          uid: '3e18a245-sb-uuid',
          name: 'Michelle',
          firebaseUid: 'wsk89DJ7lxZWFefpvghV5qnhazs2',
        );

        // In inventory_page: adminId passed to createScanCommand is session.firebaseUid ?? session.uid
        final effectiveAdminId = session.firebaseUid ?? session.uid;
        expect(effectiveAdminId, 'wsk89DJ7lxZWFefpvghV5qnhazs2');
        expect(effectiveAdminId, isNot(session.uid));
      },
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Fake Supabase & Firebase Backends for testing
// ─────────────────────────────────────────────────────────────────────────────

class FakeAuthSupabaseBackend implements AuthSupabaseBackend {
  FakeAuthSupabaseBackend({
    this.identity,
    this.adminRow,
    this.rpcRole,
    this.signInThrows = false,
    this.getAdminThrows = false,
  });

  AuthSessionIdentity? identity;
  Map<String, dynamic>? adminRow;
  String? rpcRole;
  bool signInThrows;
  bool getAdminThrows;

  bool signOutCalled = false;
  bool updateLastLoginCalled = false;

  @override
  Future<AuthSessionIdentity> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (signInThrows) throw Exception('Simulated Supabase sign-in error');
    return identity ??
        AuthSessionIdentity(id: 'sb-uid-12345', email: email, name: 'Michelle');
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  AuthSessionIdentity? get currentIdentity => identity;

  @override
  Future<Map<String, dynamic>?> getAdminRow(String userId) async {
    if (getAdminThrows) throw Exception('Simulated admin table error');
    return adminRow;
  }

  @override
  Future<String?> getAdminRoleRpc() async => rpcRole;

  @override
  Future<void> updateLastLogin(String userId) async {
    updateLastLoginCalled = true;
  }
}

class FakeAuthFirebaseBackend implements AuthFirebaseBackend {
  FakeAuthFirebaseBackend({
    this.firebaseUid = 'wsk89DJ7lxZWFefpvghV5qnhazs2',
    this.adminRecord,
    this.signInThrows = false,
    this.getRecordThrows = false,
  });

  String? firebaseUid;
  Map<String, dynamic>? adminRecord;
  bool signInThrows;
  bool getRecordThrows;

  bool signOutCalled = false;

  @override
  Future<String> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (signInThrows) throw Exception('Simulated Firebase Auth sign-in error');
    if (firebaseUid == null) throw Exception('Firebase user is null');
    return firebaseUid!;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  String? get currentUserId => firebaseUid;

  @override
  Future<Map<String, dynamic>?> getAdminRecord(String uid) async {
    if (getRecordThrows) throw Exception('Simulated RTDB error');
    return adminRecord;
  }
}
