import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/services/password_recovery_service.dart';

void main() {
  group('PasswordRecoveryService', () {
    late _FakeRecoveryAuth auth;
    late PasswordRecoveryService service;

    setUp(() {
      auth = _FakeRecoveryAuth();
      service = PasswordRecoveryService(auth);
    });

    test('normalizes the email before requesting a recovery code', () async {
      await service.sendRecoveryCode(email: ' Admin@Example.com ');

      expect(auth.requestedEmail, 'admin@example.com');
    });

    test(
      'requires an active Main Admin or Co-Admin after OTP verification',
      () async {
        auth.identity = const PasswordRecoveryIdentity(
          id: 'user-1',
          email: 'admin@example.com',
        );
        auth.role = null;

        await expectLater(
          service.verifyRecoveryCode(
            email: 'admin@example.com',
            code: '123456',
          ),
          throwsA(isA<PasswordRecoveryException>()),
        );

        expect(auth.signOutCalls, 1);
        expect(auth.updatedPassword, isNull);
      },
    );

    test('rejects a recovery session for a different email', () async {
      auth.identity = const PasswordRecoveryIdentity(
        id: 'user-1',
        email: 'other@example.com',
      );

      await expectLater(
        service.verifyRecoveryCode(email: 'admin@example.com', code: '123456'),
        throwsA(isA<PasswordRecoveryException>()),
      );

      expect(auth.signOutCalls, 1);
    });

    test(
      'allows active Co-Admin recovery and signs out after password update',
      () async {
        auth.identity = const PasswordRecoveryIdentity(
          id: 'user-1',
          email: 'admin@example.com',
        );
        auth.role = 'co_admin';
        auth.currentUserId = 'user-1';

        await service.verifyRecoveryCode(
          email: 'admin@example.com',
          code: '123456',
        );
        await service.resetPassword(newPassword: 'new-password');

        expect(auth.updatedPassword, 'new-password');
        expect(auth.signOutCalls, 1);
        expect(auth.currentUserId, isNull);
      },
    );

    test(
      'rechecks active role immediately before resetting the password',
      () async {
        auth.identity = const PasswordRecoveryIdentity(
          id: 'user-1',
          email: 'admin@example.com',
        );
        auth.role = 'main_admin';
        auth.currentUserId = 'user-1';

        await service.verifyRecoveryCode(
          email: 'admin@example.com',
          code: '123456',
        );
        auth.role = null;

        await expectLater(
          service.resetPassword(newPassword: 'new-password'),
          throwsA(isA<PasswordRecoveryException>()),
        );

        expect(auth.updatedPassword, isNull);
        expect(auth.signOutCalls, 1);
      },
    );

    test(
      'requires the same verified Auth session for password reset',
      () async {
        auth.identity = const PasswordRecoveryIdentity(
          id: 'user-1',
          email: 'admin@example.com',
        );
        auth.role = 'main_admin';
        auth.currentUserId = 'different-user';

        await service.verifyRecoveryCode(
          email: 'admin@example.com',
          code: '123456',
        );

        await expectLater(
          service.resetPassword(newPassword: 'new-password'),
          throwsA(isA<PasswordRecoveryException>()),
        );

        expect(auth.updatedPassword, isNull);
      },
    );
  });
}

class _FakeRecoveryAuth implements PasswordRecoveryAuthClient {
  String? requestedEmail;
  PasswordRecoveryIdentity? identity;
  String? role = 'main_admin';
  @override
  String? currentUserId;
  String? updatedPassword;
  int signOutCalls = 0;

  @override
  Future<String?> getActiveAdminRole() async => role;

  @override
  Future<void> sendRecoveryCode(String email) async {
    requestedEmail = email;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentUserId = null;
  }

  @override
  Future<void> updatePassword(String password) async {
    updatedPassword = password;
  }

  @override
  Future<PasswordRecoveryIdentity?> verifyRecoveryCode({
    required String email,
    required String code,
  }) async => identity;
}
