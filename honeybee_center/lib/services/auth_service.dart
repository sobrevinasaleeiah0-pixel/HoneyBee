import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_database/firebase_database.dart' as fb_db;

import 'password_recovery_service.dart';

enum UserRole { mainAdmin, coAdmin }

extension UserRoleLabel on UserRole {
  String get label => this == UserRole.mainAdmin ? 'Owner' : 'Co-Admin';
  String get value => this == UserRole.mainAdmin ? 'main_admin' : 'co_admin';
}

/// Maps a raw admin role string from `public.admins` or Firebase RTDB to a [UserRole].
///
/// Deny-by-default: only the two known role strings are accepted. A missing,
/// null, or unrecognized value returns `null` so callers sign the user out
/// instead of silently defaulting to Co-Admin. The database CHECK constraint
/// already limits `admins.role` to these values; this is defense-in-depth.
UserRole? tryParseAdminRole(String? roleStr) {
  switch (roleStr) {
    case 'main_admin':
      return UserRole.mainAdmin;
    case 'co_admin':
      return UserRole.coAdmin;
    default:
      return null;
  }
}

class AuthSession {
  const AuthSession({
    required this.email,
    required this.role,
    required this.uid,
    required this.name,
    this.firebaseUid,
  });

  final String email;
  final UserRole role;
  final String uid; // Supabase UID
  final String name;
  final String? firebaseUid; // Firebase Auth UID
}

// ─────────────────────────────────────────────────────────────────────────────
// Injectable backend interfaces for dual authentication (Supabase + Firebase)
// ─────────────────────────────────────────────────────────────────────────────

class AuthSessionIdentity {
  const AuthSessionIdentity({required this.id, required this.email, this.name});
  final String id;
  final String email;
  final String? name;
}

abstract interface class AuthSupabaseBackend {
  Future<AuthSessionIdentity> signInWithPassword({
    required String email,
    required String password,
  });
  Future<void> signOut();
  AuthSessionIdentity? get currentIdentity;
  Future<Map<String, dynamic>?> getAdminRow(String userId);
  Future<String?> getAdminRoleRpc();
  Future<void> updateLastLogin(String userId);
}

abstract interface class AuthFirebaseBackend {
  Future<String> signInWithEmailAndPassword({
    required String email,
    required String password,
  });
  Future<void> signOut();
  String? get currentUserId;
  Future<Map<String, dynamic>?> getAdminRecord(String firebaseUid);
}

class ProductionAuthSupabaseBackend implements AuthSupabaseBackend {
  ProductionAuthSupabaseBackend([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<AuthSessionIdentity> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw Exception('User authentication failed.');
    }
    final name =
        user.userMetadata?['name'] ??
        user.userMetadata?['full_name'] ??
        'Admin';
    return AuthSessionIdentity(
      id: user.id,
      email: user.email ?? email.trim(),
      name: name.toString(),
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  @override
  AuthSessionIdentity? get currentIdentity {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final name =
        user.userMetadata?['name'] ??
        user.userMetadata?['full_name'] ??
        'Admin';
    return AuthSessionIdentity(
      id: user.id,
      email: user.email ?? '',
      name: name.toString(),
    );
  }

  @override
  Future<Map<String, dynamic>?> getAdminRow(String userId) async {
    final adminRow = await _client
        .from('admins')
        .select('name, role, status')
        .eq('id', userId)
        .maybeSingle();
    if (adminRow == null) return null;
    return Map<String, dynamic>.from(adminRow);
  }

  @override
  Future<String?> getAdminRoleRpc() async {
    final rpcRole = await _client.rpc('get_admin_role');
    return rpcRole?.toString();
  }

  @override
  Future<void> updateLastLogin(String userId) async {
    try {
      await _client
          .from('admins')
          .update({'last_login': DateTime.now().toUtc().toIso8601String()})
          .eq('id', userId);
    } catch (_) {
      // Silently continue if update is restricted under RLS
    }
  }
}

class ProductionAuthFirebaseBackend implements AuthFirebaseBackend {
  ProductionAuthFirebaseBackend({
    fb_auth.FirebaseAuth? auth,
    fb_db.FirebaseDatabase? db,
  }) : _auth = auth ?? fb_auth.FirebaseAuth.instance,
       _db = db ?? fb_db.FirebaseDatabase.instance;

  final fb_auth.FirebaseAuth _auth;
  final fb_db.FirebaseDatabase _db;

  @override
  Future<String> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user;
    if (user == null) {
      throw Exception('Firebase authentication returned no user session.');
    }
    return user.uid;
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  @override
  Future<Map<String, dynamic>?> getAdminRecord(String firebaseUid) async {
    final snap = await _db.ref('admins/$firebaseUid').get();
    if (!snap.exists || snap.value == null) return null;
    if (snap.value is! Map) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthService Implementation with Supabase Authentication
// ─────────────────────────────────────────────────────────────────────────────

class AuthService {
  AuthService({
    AuthSupabaseBackend? supabaseBackend,
    AuthFirebaseBackend? firebaseBackend,
  }) : _supabaseBackend = supabaseBackend,
       _firebaseBackend = firebaseBackend;

  AuthSupabaseBackend? _supabaseBackend;
  AuthFirebaseBackend? _firebaseBackend;

  static const Duration _firebaseOperationTimeout = Duration(seconds: 5);

  AuthSupabaseBackend get _requiredSupabaseBackend =>
      _supabaseBackend ??= ProductionAuthSupabaseBackend();

  AuthFirebaseBackend? get _optionalFirebaseBackend {
    if (_firebaseBackend != null) return _firebaseBackend;
    if (Firebase.apps.isEmpty) return null;
    return _firebaseBackend = ProductionAuthFirebaseBackend();
  }

  Future<String?> _establishOptionalFirebaseSession({
    required AuthFirebaseBackend backend,
    required String email,
    required String password,
  }) async {
    final firebaseUid = await backend.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final adminRecord = await backend.getAdminRecord(firebaseUid);
    if (adminRecord == null) return firebaseUid;

    final status = adminRecord['status']?.toString();
    final isActive = adminRecord['isActive'] == true || status == 'active';
    if (!isActive) {
      debugPrint(
        '[AuthService] Firebase record is marked inactive; skipping Firebase IoT session.',
      );
      return null;
    }

    return firebaseUid;
  }

  SupabaseClient get _supabase => Supabase.instance.client;

  static const int minimumPasswordLength = 8;

  /// Signs in an administrator with Supabase; Firebase is an optional IoT session.
  ///
  /// Flow:
  /// 1. Authenticate with Supabase Auth (primary business authority).
  /// 2. Verify active status and role in Supabase `public.admins`.
  /// 3. Optionally establish a Firebase IoT session; failures do not block access.
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();

    // ── STEP 1: Authenticate with Supabase ─────────────────────────────────
    AuthSessionIdentity supabaseIdentity;
    try {
      supabaseIdentity = await _requiredSupabaseBackend.signInWithPassword(
        email: trimmedEmail,
        password: password,
      );
    } on AuthException catch (e) {
      debugPrint('[AuthService] Supabase AuthException: ${e.message}');
      throw Exception(e.message);
    } catch (e) {
      debugPrint('[AuthService] Supabase signIn error: $e');
      throw Exception('Supabase authentication failed: $e');
    }

    // ── STEP 2: Verify active administrator in Supabase ────────────────────
    String? roleStr;
    String name = supabaseIdentity.name ?? 'Admin';

    try {
      final adminRow = await _requiredSupabaseBackend.getAdminRow(
        supabaseIdentity.id,
      );
      if (adminRow != null) {
        final status = adminRow['status'] as String? ?? 'active';
        if (status != 'active') {
          await _requiredSupabaseBackend.signOut();
          throw Exception(
            'This account is currently $status. Please contact the system owner.',
          );
        }
        roleStr = adminRow['role'] as String?;
        name = adminRow['name'] as String? ?? name;
      } else {
        // Fallback to get_admin_role SECURITY DEFINER RPC
        final rpcRole = await _requiredSupabaseBackend.getAdminRoleRpc();
        if (rpcRole == null) {
          await _requiredSupabaseBackend.signOut();
          throw Exception(
            'Access denied. No active administrative record found.',
          );
        }
        roleStr = rpcRole;
      }
    } catch (err) {
      if (err.toString().contains('is currently') ||
          err.toString().contains('Access denied')) {
        rethrow;
      }
      // Direct table select restricted -> verify via get_admin_role RPC
      final rpcRole = await _requiredSupabaseBackend.getAdminRoleRpc();
      if (rpcRole == null) {
        await _requiredSupabaseBackend.signOut();
        throw Exception(
          'Access denied. No active administrative record found.',
        );
      }
      roleStr = rpcRole;
    }

    final role = tryParseAdminRole(roleStr);
    if (role == null) {
      await _requiredSupabaseBackend.signOut();
      throw Exception('Access denied. Unrecognized administrator role.');
    }

    // Firebase authentication is optional and must not delay Supabase access.
    String? firebaseUid;
    AuthFirebaseBackend? firebaseBackend;
    try {
      firebaseBackend = _optionalFirebaseBackend;
    } catch (fbErr) {
      debugPrint('[AuthService] Optional Firebase backend unavailable: $fbErr');
    }
    if (firebaseBackend == null) {
      debugPrint(
        '[AuthService] Firebase is not initialized; continuing with Supabase only.',
      );
    } else {
      try {
        firebaseUid = await _establishOptionalFirebaseSession(
          backend: firebaseBackend,
          email: trimmedEmail,
          password: password,
        ).timeout(_firebaseOperationTimeout);
      } catch (fbErr) {
        debugPrint(
          '[AuthService] Optional Firebase sign-in skipped or failed: $fbErr',
        );
      }
    }

    // ── STEP 4: Best-effort update last_login in Supabase ───────────────────
    await _requiredSupabaseBackend.updateLastLogin(supabaseIdentity.id);

    return AuthSession(
      email: supabaseIdentity.email,
      role: role,
      uid: supabaseIdentity.id,
      name: name,
      firebaseUid: firebaseUid,
    );
  }

  /// Signs out of both Supabase and Firebase Auth.
  /// Handles partial logout failures cleanly to avoid leaving dangling sessions.
  Future<void> signOut() async {
    Object? firstError;
    try {
      await _requiredSupabaseBackend.signOut();
    } catch (e) {
      firstError = e;
      debugPrint('[AuthService] Error signing out of Supabase: $e');
    }

    AuthFirebaseBackend? firebaseBackend;
    try {
      firebaseBackend = _optionalFirebaseBackend;
    } catch (e) {
      firstError ??= e;
      debugPrint('[AuthService] Firebase sign-out unavailable: $e');
    }
    if (firebaseBackend != null) {
      try {
        await firebaseBackend.signOut().timeout(_firebaseOperationTimeout);
      } catch (e) {
        firstError ??= e;
        debugPrint('[AuthService] Error signing out of Firebase: $e');
      }
    }

    if (firstError != null) {
      debugPrint('[AuthService] Partial logout encountered: $firstError');
    }
  }

  /// Restores the current authenticated administrative session.
  /// Returns null if Supabase session is missing or if the admin account is inactive.
  Future<AuthSession?> getCurrentSession() async {
    final supabaseIdentity = _requiredSupabaseBackend.currentIdentity;
    if (supabaseIdentity == null) return null;

    try {
      String? roleStr;
      String name = supabaseIdentity.name ?? 'Admin';

      try {
        final adminRow = await _requiredSupabaseBackend.getAdminRow(
          supabaseIdentity.id,
        );
        if (adminRow != null) {
          final status = adminRow['status'] as String? ?? 'active';
          if (status != 'active') {
            await signOut();
            return null;
          }
          roleStr = adminRow['role'] as String?;
          name = adminRow['name'] as String? ?? name;
        } else {
          final rpcRole = await _requiredSupabaseBackend.getAdminRoleRpc();
          if (rpcRole == null) {
            await signOut();
            return null;
          }
          roleStr = rpcRole;
        }
      } catch (_) {
        final rpcRole = await _requiredSupabaseBackend.getAdminRoleRpc();
        if (rpcRole == null) {
          await signOut();
          return null;
        }
        roleStr = rpcRole;
      }

      final role = tryParseAdminRole(roleStr);
      if (role == null) {
        await signOut();
        return null;
      }

      String? fbUid;
      try {
        fbUid = _optionalFirebaseBackend?.currentUserId;
      } catch (e) {
        debugPrint('[AuthService] Optional Firebase session unavailable: $e');
      }

      return AuthSession(
        email: supabaseIdentity.email,
        role: role,
        uid: supabaseIdentity.id,
        name: name,
        firebaseUid: fbUid,
      );
    } catch (e) {
      debugPrint('[AuthService] getCurrentSession error: $e');
      return null;
    }
  }

  /// Sends a six-digit recovery code through Supabase Auth.
  Future<void> sendPasswordReset({required String email}) async {
    await PasswordRecoveryService.supabase().sendRecoveryCode(email: email);
  }

  /// Changes the current administrator's password in Supabase.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No user is currently logged in.');
    }

    try {
      // Re-verify current password first
      await _supabase.auth.signInWithPassword(
        email: user.email!,
        password: currentPassword,
      );
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw Exception(e.message);
    }
  }

  /// Creates a Co-Admin account in Supabase.
  /// (Placeholder until admin user-provisioning Edge Function is deployed)
  Future<void> createCoAdmin({
    required String fullName,
    required String email,
    required String password,
    required String creatorId,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'name': fullName, 'role': 'co_admin'},
      );
      if (response.user == null) {
        throw Exception('Failed to create account.');
      }
    } on AuthException catch (e) {
      throw Exception(e.message);
    }
  }

  static String? validateFullName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Full Name cannot be empty.';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Email cannot be empty.';
    }
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password cannot be empty.';
    }
    if (value.length < minimumPasswordLength) {
      return 'Password must be at least $minimumPasswordLength characters.';
    }
    return null;
  }

  static String? validateConfirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Confirm Password cannot be empty.';
    }
    if (value != password) {
      return 'Passwords do not match.';
    }
    return null;
  }
}
