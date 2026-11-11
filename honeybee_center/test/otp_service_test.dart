import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:honeybee_center/config/supabase_config.dart';
import 'package:honeybee_center/services/otp_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('OtpService', () {
    test('sends normalized email with the Supabase function headers', () async {
      http.Request? capturedRequest;
      final service = OtpService.forTesting(
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode({'success': true, 'message': 'Generic response.'}),
            200,
          );
        }),
      );

      final result = await service.sendOtp(email: ' Admin@Example.com ');

      expect(result.success, isTrue);
      expect(capturedRequest!.url.path, '/functions/v1/otp');
      expect(capturedRequest!.url.origin, SupabaseConfig.url);
      expect(capturedRequest!.headers['apikey'], isNotEmpty);
      expect(jsonDecode(capturedRequest!.body), {
        'action': 'requestOtp',
        'email': 'admin@example.com',
      });
    });

    test(
      'accepts generic successful request without an account session id',
      () async {
        final service = OtpService.forTesting(
          client: MockClient(
            (_) async => http.Response(jsonEncode({'success': true}), 200),
          ),
        );

        expect(
          (await service.sendOtp(email: 'admin@example.com')).success,
          isTrue,
        );
      },
    );

    test('accepts the outbox queued response status', () async {
      final service = OtpService.forTesting(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'success': true, 'message': 'Generic response.'}),
            202,
          ),
        ),
      );

      expect((await service.sendOtp(email: 'admin@example.com')).success, isTrue);
    });

    test('surfaces unsuccessful OTP request response', () async {
      final service = OtpService.forTesting(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'success': false, 'message': 'Try again.'}),
            400,
          ),
        ),
      );

      await expectLater(
        service.sendOtp(email: 'admin@example.com'),
        throwsA(
          isA<OtpServiceException>().having(
            (error) => error.message,
            'message',
            'Try again.',
          ),
        ),
      );
    });

    test(
      'verifies with normalized email and returns the reset token',
      () async {
        http.Request? capturedRequest;
        final service = OtpService.forTesting(
          client: MockClient((request) async {
            capturedRequest = request;
            return http.Response(
              jsonEncode({'success': true, 'resetToken': 'verified-token'}),
              200,
            );
          }),
        );

        final result = await service.verifyOtp(
          email: ' Admin@Example.com ',
          otp: ' 123456 ',
        );

        expect(result.success, isTrue);
        expect(result.verifiedToken, 'verified-token');
        expect(jsonDecode(capturedRequest!.body), {
          'action': 'verifyOtp',
          'email': 'admin@example.com',
          'otp': '123456',
        });
      },
    );

    test('rejects a reset token when verification is not successful', () async {
      final service = OtpService.forTesting(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'success': false, 'resetToken': 'unexpected-token'}),
            200,
          ),
        ),
      );

      await expectLater(
        service.verifyOtp(email: 'admin@example.com', otp: '123456'),
        throwsA(isA<OtpServiceException>()),
      );
    });

    test(
      'completes password reset only on an explicit success response',
      () async {
        http.Request? capturedRequest;
        final service = OtpService.forTesting(
          client: MockClient((request) async {
            capturedRequest = request;
            return http.Response(jsonEncode({'success': true}), 200);
          }),
        );

        await service.resetPassword(
          verifiedToken: 'verified-token',
          newPassword: 'new-password',
        );

        expect(jsonDecode(capturedRequest!.body), {
          'action': 'completePasswordReset',
          'resetToken': 'verified-token',
          'newPassword': 'new-password',
        });
      },
    );

    test('surfaces password reset failure responses', () async {
      final service = OtpService.forTesting(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'success': false, 'message': 'Reset failed.'}),
            500,
          ),
        ),
      );

      await expectLater(
        service.resetPassword(
          verifiedToken: 'verified-token',
          newPassword: 'new-password',
        ),
        throwsA(isA<OtpServiceException>()),
      );
    });
  });
}
