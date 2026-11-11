import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordRecoveryIdentity {
  const PasswordRecoveryIdentity({required this.id, required this.email});

  final String id;
  final String? email;
}

abstract interface class PasswordRecoveryAuthClient {
  String? get currentUserId;

  Future<void> sendRecoveryCode(String email);

  Future<PasswordRecoveryIdentity?> verifyRecoveryCode({
    required String email,
    required String code,
  });

  Future<String?> getActiveAdminRole();

  Future<void> updatePassword(String password);

  Future<void> signOut();
}

class SupabasePasswordRecoveryAuthClient implements PasswordRecoveryAuthClient {
  SupabasePasswordRecoveryAuthClient(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<void> sendRecoveryCode(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } on AuthException catch (error) {
      throw PasswordRecoveryException(error.message);
    }
  }

  @override
  Future<PasswordRecoveryIdentity?> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.recovery,
      );
      final user = response.user ?? _client.auth.currentUser;
      if (user == null) return null;
      return PasswordRecoveryIdentity(id: user.id, email: user.email);
    } on AuthException catch (error) {
      throw PasswordRecoveryException(error.message);
    }
  }

  @override
  Future<String?> getActiveAdminRole() async {
    final role = await _client.rpc('get_admin_role');
    return role?.toString();
  }

  @override
  Future<void> updatePassword(String password) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (error) {
      throw PasswordRecoveryException(error.message);
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

class PasswordRecoveryService {
  PasswordRecoveryService(this._auth);

  PasswordRecoveryService.supabase()
    : this(SupabasePasswordRecoveryAuthClient(Supabase.instance.client));

  final PasswordRecoveryAuthClient _auth;
  String? _verifiedUserId;

  Future<void> sendRecoveryCode({required String email}) {
    return _auth.sendRecoveryCode(email.trim().toLowerCase());
  }

  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final identity = await _auth.verifyRecoveryCode(
      email: normalizedEmail,
      code: code.trim(),
    );

    if (identity == null ||
        identity.email?.trim().toLowerCase() != normalizedEmail) {
      await _auth.signOut();
      throw const PasswordRecoveryException(
        'The verification code is invalid or expired. Please request a new code.',
      );
    }

    final role = await _auth.getActiveAdminRole();
    if (role != 'main_admin' && role != 'co_admin') {
      await _auth.signOut();
      throw const PasswordRecoveryException(
        'No active administrator account was found for this email.',
      );
    }

    _verifiedUserId = identity.id;
  }

  Future<void> resetPassword({required String newPassword}) async {
    final verifiedUserId = _verifiedUserId;
    if (verifiedUserId == null || _auth.currentUserId != verifiedUserId) {
      throw const PasswordRecoveryException(
        'Please verify a new recovery code before resetting your password.',
      );
    }

    final role = await _auth.getActiveAdminRole();
    if (role != 'main_admin' && role != 'co_admin') {
      _verifiedUserId = null;
      await _auth.signOut();
      throw const PasswordRecoveryException(
        'This administrator account is no longer active.',
      );
    }

    await _auth.updatePassword(newPassword);
    _verifiedUserId = null;
    await _auth.signOut();
  }

  Future<void> cancel() async {
    if (_verifiedUserId != null) {
      _verifiedUserId = null;
      await _auth.signOut();
    }
  }
}

class PasswordRecoveryException implements Exception {
  const PasswordRecoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}
