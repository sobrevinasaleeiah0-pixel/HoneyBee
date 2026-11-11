import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────────────

class SendOtpResult {
  final bool success;

  const SendOtpResult({
    required this.success,
  });
}

class VerifyOtpResult {
  final bool success;
  final String verifiedToken;

  const VerifyOtpResult({
    required this.success,
    required this.verifiedToken,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// OtpService
//
// Uses the Supabase Edge Function as the secure OTP backend.
//
// Flutter Web
//     ↓
// Supabase Edge Function
//     ↓
// Supabase Auth / PostgreSQL
//
// No service-role key or SMTP credentials are stored in the client.
// ─────────────────────────────────────────────────────────────────────────────

class OtpService {
  OtpService._({http.Client? client}) : _client = client ?? http.Client();

  static final OtpService instance = OtpService._();
  @visibleForTesting
  OtpService.forTesting({required http.Client client}) : this._(client: client);

  final http.Client _client;

  static const String _functionUrl = String.fromEnvironment(
    'OTP_FUNCTION_URL',
    defaultValue: '${SupabaseConfig.url}/functions/v1/otp',
  );
  static final Uri _functionUri = Uri.parse(_functionUrl);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Send OTP
  // ─────────────────────────────────────────────────────────────────────────

  Future<SendOtpResult> sendOtp({
    required String email,
  }) async {
    try {
      final response = await _client.post(
        _functionUri,
        headers: _headers,
        body: jsonEncode({
          'action': 'requestOtp',
          'email': email.trim().toLowerCase(),
        }),
      );

      final data = _decodeResponse(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OtpServiceException(
          data['message']?.toString() ??
              'Unable to send verification code. Please try again.',
        );
      }

      if (data['success'] != true) {
        throw OtpServiceException(
          data['message']?.toString() ??
              'Unable to send verification code. Please try again.',
        );
      }

      return const SendOtpResult(success: true);
    } on OtpServiceException {
      rethrow;
    } catch (_) {
      throw const OtpServiceException(
        'Unable to connect to the server. Please check your connection.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Verify OTP
  // ─────────────────────────────────────────────────────────────────────────

  Future<VerifyOtpResult> verifyOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _client.post(
        _functionUri,
        headers: _headers,
        body: jsonEncode({
          'action': 'verifyOtp',
          'email': email.trim().toLowerCase(),
          'otp': otp.trim(),
        }),
      );

      final data = _decodeResponse(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OtpServiceException(
          data['message']?.toString() ??
              'Invalid verification code. Please try again.',
        );
      }

      final resetToken = data['resetToken']?.toString();

      if (data['success'] != true ||
          resetToken == null ||
          resetToken.isEmpty) {
        throw const OtpServiceException(
          'Invalid verification response. Please request a new code.',
        );
      }

      return VerifyOtpResult(
        success: data['success'] == true,
        verifiedToken: resetToken,
      );
    } on OtpServiceException {
      rethrow;
    } catch (_) {
      throw const OtpServiceException(
        'Unable to connect to the server. Please check your connection.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Complete Password Reset
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> resetPassword({
    required String verifiedToken,
    required String newPassword,
  }) async {
    try {
      final response = await _client.post(
        _functionUri,
        headers: _headers,
        body: jsonEncode({
          'action': 'completePasswordReset',
          'resetToken': verifiedToken,
          'newPassword': newPassword,
        }),
      );

      final data = _decodeResponse(response);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OtpServiceException(
          data['message']?.toString() ??
              'Unable to complete password reset. Please try again.',
        );
      }

      if (data['success'] != true) {
        throw OtpServiceException(
          data['message']?.toString() ??
              'Unable to complete password reset. Please try again.',
        );
      }
    } on OtpServiceException {
      rethrow;
    } catch (_) {
      throw const OtpServiceException(
        'Unable to connect to the server. Please check your connection.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Response helper
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      throw const OtpServiceException(
        'The server returned an invalid response. Please try again.',
      );
    }
    throw const OtpServiceException(
      'The server returned an invalid response. Please try again.',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OtpServiceException
// ─────────────────────────────────────────────────────────────────────────────

class OtpServiceException implements Exception {
  final String message;

  const OtpServiceException(this.message);

  @override
  String toString() => message;
}