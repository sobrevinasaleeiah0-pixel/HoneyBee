import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/password_recovery_service.dart';
import '../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ForgotPasswordPage
//
// Uses Supabase Auth's six-digit recovery OTP flow.
//
// Flow:
//   Step 1 – Enter email → resetPasswordForEmail
//   Step 2 – Enter 6-digit OTP → verifyOTP (recovery)
//   Step 3 – Enter new password → updateUser
//   Step 4 – Success screen → Back to Login
// ─────────────────────────────────────────────────────────────────────────────

enum _Step { email, otp, newPassword, success }

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage>
    with SingleTickerProviderStateMixin {
  _Step _step = _Step.email;

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _otpFocusNode = FocusNode();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _recoveryService = PasswordRecoveryService.supabase();
  bool _isLoading = false;
  bool _showNewPassword = false;
  bool _showConfirmPassword = false;
  int _resendSecondsRemaining = 0;
  Timer? _resendTimer;
  String? _errorMessage;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  // ── Amber/gold palette matching login_page.dart ──
  static const _gold = Color(0xFFD9A441);
  static const _goldDark = Color(0xFFC89127);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _otpFocusNode.addListener(_onOtpFocusChanged);
  }

  void _onOtpFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _otpFocusNode
      ..removeListener(_onOtpFocusChanged)
      ..dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _resendTimer?.cancel();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  Future<void> _onSendOtp() async {
    _clearError();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _recoveryService.sendRecoveryCode(email: _emailCtrl.text.trim());
      if (!mounted) return;
      _startResendCooldown();

      _fadeCtrl.reverse().then((_) {
        if (mounted) {
          setState(() => _step = _Step.otp);
          _fadeCtrl.forward();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onResendOtp() async {
    _clearError();
    setState(() => _isLoading = true);
    try {
      await _recoveryService.sendRecoveryCode(email: _emailCtrl.text.trim());
      if (mounted) _startResendCooldown();
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsRemaining = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendSecondsRemaining <= 1) {
          _resendSecondsRemaining = 0;
          timer.cancel();
        } else {
          _resendSecondsRemaining--;
        }
      });
    });
  }

  Future<void> _onVerifyOtp() async {
    _clearError();
    if (_otpCtrl.text.trim().length != 6) {
      setState(
        () => _errorMessage = 'Please enter the 6-digit verification code.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _recoveryService.verifyRecoveryCode(
        email: _emailCtrl.text.trim(),
        code: _otpCtrl.text.trim(),
      );
      if (!mounted) return;

      _fadeCtrl.reverse().then((_) {
        if (mounted) {
          setState(() => _step = _Step.newPassword);
          _fadeCtrl.forward();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onResetPassword() async {
    _clearError();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await _recoveryService.resetPassword(
        newPassword: _newPasswordCtrl.text.trim(),
      );
      if (!mounted) return;

      _fadeCtrl.reverse().then((_) {
        if (mounted) {
          setState(() => _step = _Step.success);
          _fadeCtrl.forward();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppTheme.backgroundDark
          : AppTheme.backgroundLight,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!isDark)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF0D0),
                    Color(0xFFFFFBF3),
                    Color(0xFFFFFBF3),
                    Color(0xFFFFF4E0),
                  ],
                  stops: [0.0, 0.25, 0.65, 1.0],
                ),
              ),
            )
          else
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1C170A),
                    Color(0xFF14130F),
                    Color(0xFF14130F),
                    Color(0xFF1A160D),
                  ],
                  stops: [0.0, 0.25, 0.65, 1.0],
                ),
              ),
            ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.surfaceDark
                          : AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF3A2D10)
                            : const Color(0xFFE8D1A0),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? const Color(0xFF080705)
                              : const Color(0xFFE2D3B0),
                          blurRadius: 32,
                          spreadRadius: 2,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 44,
                    ),
                    child: _buildStepContent(isDark),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step content builder ─────────────────────────────────────────────────────
  Widget _buildStepContent(bool isDark) {
    switch (_step) {
      case _Step.email:
        return _buildEmailStep(isDark);
      case _Step.otp:
        return _buildOtpStep(isDark);
      case _Step.newPassword:
        return _buildNewPasswordStep(isDark);
      case _Step.success:
        return _buildSuccessStep(isDark);
    }
  }

  // ── Step 1: Email entry ────────────────────────────────────────────────────
  Widget _buildEmailStep(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon badge
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  isDark ? const Color(0xFF3A2A10) : const Color(0xFFFDF0D5),
                  isDark ? const Color(0xFF3A2D10) : const Color(0xFFFBF1DD),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? const Color(0xFF6B5220)
                    : const Color(0xFFE8D1A0),
                width: 1.6,
              ),
            ),
            child: const Icon(Icons.lock_reset_rounded, color: _gold, size: 32),
          ),
        ),
        const SizedBox(height: 18),

        // Title
        Text(
          'Honeybee Center',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Forgot Password',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF888888),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter your admin email. If it belongs to an active account,\n'
          'we\'ll send a 6-digit verification code.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white60 : const Color(0xFFAAAAAA),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),

        // Divider
        Container(
          height: 1,
          color: isDark ? const Color(0xFF2A2620) : const Color(0xFFEEEEEE),
        ),
        const SizedBox(height: 24),

        // Error banner
        if (_errorMessage != null) ...[
          _ErrorBanner(message: _errorMessage!),
          const SizedBox(height: 16),
        ],

        // Email label
        Text(
          'Email Address',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 8),

        // Email field
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _emailCtrl,
            enabled: !_isLoading,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            ),
            onChanged: (_) => _clearError(),
            decoration: InputDecoration(
              hintText: 'Enter your registered email',
              hintStyle: TextStyle(
                color: isDark ? Colors.white38 : const Color(0xFFBBBBBB),
                fontSize: 13,
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A2D10)
                      : const Color(0xFFFBF1DD),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.email_outlined, size: 17, color: _gold),
              ),
              filled: true,
              fillColor: isDark
                  ? AppTheme.backgroundDarkAlt
                  : const Color(0xFFFAFAFA),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF2A2620)
                      : const Color(0xFFE0E0E0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark
                      ? const Color(0xFF2A2620)
                      : const Color(0xFFE0E0E0),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _gold, width: 1.6),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 1.2,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 1.6,
                ),
              ),
            ),
            validator: AuthService.validateEmail,
          ),
        ),
        const SizedBox(height: 10),

        // Info hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF6B5220) : const Color(0xFFE8D1A0),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 15,
                color: Color(0xFFC89127),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'If this email is registered, a 6-digit code will '
                  'be sent. Check your inbox (and spam folder).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7A6300),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Send button
        _GoldButton(
          label: 'Send Verification Code',
          loadingLabel: 'Sending...',
          isLoading: _isLoading,
          onPressed: _onSendOtp,
        ),
        const SizedBox(height: 18),

        // Back to login
        _BackLink(onTap: () => Navigator.of(context).pop()),
      ],
    );
  }

  // ── Step 2: OTP entry ───────────────────────────────────────────────────────
  Widget _buildOtpStep(bool isDark) {
    final email = _emailCtrl.text.trim();
    final digits = _otpCtrl.text;
    final activeIndex = digits.length;
    final emptyBorder = isDark
        ? const Color(0xFF39332A)
        : const Color(0xFFE9E1D3);
    final emptyFill = isDark
        ? AppTheme.backgroundDarkAlt
        : const Color(0xFFFFFCF6);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < 4; index++) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == 1 ? 28 : 18,
                height: 4,
                decoration: BoxDecoration(
                  color: index < 2
                      ? _gold
                      : (isDark
                            ? const Color(0xFF39332A)
                            : const Color(0xFFE9E1D3)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              if (index < 3) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 22),
        // Icon badge
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  isDark ? const Color(0xFF3A2A10) : const Color(0xFFFDF0D5),
                  isDark ? const Color(0xFF3A2D10) : const Color(0xFFFBF1DD),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? const Color(0xFF6B5220)
                    : const Color(0xFFE8D1A0),
                width: 1.6,
              ),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: _gold,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Title
        Text(
          'Check your inbox',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF29251E),
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),

        // Email display
        Text(
          'If this is an active account, a code will be sent to',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white70 : const Color(0xFF81796D),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF28231A) : const Color(0xFFFFF8E9),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: emptyBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.email_outlined, size: 16, color: _goldDark),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF5E5038),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Divider
        Container(
          height: 1,
          color: isDark ? const Color(0xFF2A2620) : const Color(0xFFEEEEEE),
        ),
        const SizedBox(height: 24),

        // Error banner
        if (_errorMessage != null) ...[
          _ErrorBanner(message: _errorMessage!),
          const SizedBox(height: 16),
        ],

        // OTP label
        Text(
          'Verification Code',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 8),

        // OTP input: one accessible text field styled as six separate slots.
        Form(
          key: _formKey,
          child: Semantics(
            label: 'Six-digit verification code',
            child: SizedBox(
              height: 62,
              child: Stack(
                children: [
                  Row(
                    children: List.generate(6, (index) {
                      final hasDigit = index < digits.length;
                      final isCurrent =
                          _otpFocusNode.hasFocus &&
                          index == activeIndex &&
                          !_isLoading;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: index == 5 ? 0 : 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: hasDigit
                                  ? (isDark
                                        ? const Color(0xFF332A18)
                                        : const Color(0xFFFFF5DF))
                                  : emptyFill,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isCurrent
                                    ? _gold
                                    : (hasDigit
                                          ? (isDark
                                                ? const Color(0xFF70591F)
                                                : const Color(0xFFE7C77D))
                                          : emptyBorder),
                                width: isCurrent ? 1.8 : 1.2,
                              ),
                              boxShadow: isCurrent
                                  ? [
                                      BoxShadow(
                                        color: _gold.withValues(alpha: 0.16),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              hasDigit ? digits[index] : '',
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF342B1B),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  Positioned.fill(
                    child: TextField(
                      controller: _otpCtrl,
                      focusNode: _otpFocusNode,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      showCursor: false,
                      style: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 1,
                      ),
                      cursorColor: Colors.transparent,
                      selectionControls: null,
                      onChanged: (_) {
                        _clearError();
                        setState(() {});
                      },
                      onSubmitted: (_) {
                        if (_otpCtrl.text.length == 6) _onVerifyOtp();
                      },
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        filled: false,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 15,
              color: isDark ? Colors.white54 : const Color(0xFF8A806F),
            ),
            const SizedBox(width: 6),
            Text(
              'Code expires in 5 minutes',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : const Color(0xFF8A806F),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),

        // Verify button
        _GoldButton(
          label: 'Verify and Continue',
          loadingLabel: 'Checking code...',
          isLoading: _isLoading,
          onPressed: _onVerifyOtp,
        ),
        const SizedBox(height: 14),

        Center(
          child: TextButton(
            onPressed: _isLoading || _resendSecondsRemaining > 0
                ? null
                : _onResendOtp,
            child: Text(
              _resendSecondsRemaining > 0
                  ? 'Resend code in ${_resendSecondsRemaining}s'
                  : 'Resend code',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),

        Center(
          child: TextButton.icon(
            onPressed: _isLoading
                ? null
                : () {
                    _fadeCtrl.reverse().then((_) {
                      if (mounted) {
                        setState(() => _step = _Step.email);
                        _fadeCtrl.forward();
                      }
                    });
                  },
            style: TextButton.styleFrom(
              foregroundColor: isDark
                  ? Colors.white60
                  : const Color(0xFF81796D),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.edit_outlined, size: 15),
            label: const Text(
              'Change email address',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 3: New password entry ───────────────────────────────────────────────
  Widget _buildNewPasswordStep(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Icon badge
        Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  isDark ? const Color(0xFF3A2A10) : const Color(0xFFFDF0D5),
                  isDark ? const Color(0xFF3A2D10) : const Color(0xFFFBF1DD),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? const Color(0xFF6B5220)
                    : const Color(0xFFE8D1A0),
                width: 1.6,
              ),
            ),
            child: const Icon(Icons.lock_reset_rounded, color: _gold, size: 32),
          ),
        ),
        const SizedBox(height: 18),

        // Title
        Text(
          'Set New Password',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),

        Text(
          'Enter your new password below.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white70 : const Color(0xFF888888),
          ),
        ),
        const SizedBox(height: 24),

        // Divider
        Container(
          height: 1,
          color: isDark ? const Color(0xFF2A2620) : const Color(0xFFEEEEEE),
        ),
        const SizedBox(height: 24),

        // Error banner
        if (_errorMessage != null) ...[
          _ErrorBanner(message: _errorMessage!),
          const SizedBox(height: 16),
        ],

        // New password label
        Text(
          'New Password',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF333333),
          ),
        ),
        const SizedBox(height: 8),

        // New password field
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _newPasswordCtrl,
                enabled: !_isLoading,
                obscureText: !_showNewPassword,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
                onChanged: (_) => _clearError(),
                decoration: InputDecoration(
                  hintText: 'Enter new password',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : const Color(0xFFBBBBBB),
                    fontSize: 13,
                  ),
                  prefixIcon: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A2D10)
                          : const Color(0xFFFBF1DD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 17,
                      color: _gold,
                    ),
                  ),
                  suffixIcon: IconButton(
                    tooltip: _showNewPassword
                        ? 'Hide password'
                        : 'Show password',
                    onPressed: () {
                      setState(() => _showNewPassword = !_showNewPassword);
                    },
                    icon: Icon(
                      _showNewPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? AppTheme.backgroundDarkAlt
                      : const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFF2A2620)
                          : const Color(0xFFE0E0E0),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFF2A2620)
                          : const Color(0xFFE0E0E0),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _gold, width: 1.6),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Colors.redAccent,
                      width: 1.2,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Colors.redAccent,
                      width: 1.6,
                    ),
                  ),
                ),
                validator: AuthService.validatePassword,
              ),
              const SizedBox(height: 16),

              // Confirm password label
              Text(
                'Confirm Password',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 8),

              // Confirm password field
              TextFormField(
                controller: _confirmPasswordCtrl,
                enabled: !_isLoading,
                obscureText: !_showConfirmPassword,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                ),
                onChanged: (_) => _clearError(),
                decoration: InputDecoration(
                  hintText: 'Confirm new password',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white38 : const Color(0xFFBBBBBB),
                    fontSize: 13,
                  ),
                  prefixIcon: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF3A2D10)
                          : const Color(0xFFFBF1DD),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      size: 17,
                      color: _gold,
                    ),
                  ),
                  suffixIcon: IconButton(
                    tooltip: _showConfirmPassword
                        ? 'Hide password'
                        : 'Show password',
                    onPressed: () {
                      setState(
                        () => _showConfirmPassword = !_showConfirmPassword,
                      );
                    },
                    icon: Icon(
                      _showConfirmPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? AppTheme.backgroundDarkAlt
                      : const Color(0xFFFAFAFA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFF2A2620)
                          : const Color(0xFFE0E0E0),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: isDark
                          ? const Color(0xFF2A2620)
                          : const Color(0xFFE0E0E0),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _gold, width: 1.6),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Colors.redAccent,
                      width: 1.2,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Colors.redAccent,
                      width: 1.6,
                    ),
                  ),
                ),
                validator: (value) => AuthService.validateConfirmPassword(
                  value,
                  _newPasswordCtrl.text,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Reset button
        _GoldButton(
          label: 'Reset Password',
          loadingLabel: 'Resetting...',
          isLoading: _isLoading,
          onPressed: _onResetPassword,
        ),
        const SizedBox(height: 14),

        // A verified Auth OTP is one-time, so restarting requires a new code.
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _restartRecovery,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Request a new code',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white60 : const Color(0xFF999999),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _restartRecovery() async {
    _clearError();
    setState(() => _isLoading = true);
    try {
      await _recoveryService.cancel();
      if (!mounted) return;
      _otpCtrl.clear();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      _fadeCtrl.reverse().then((_) {
        if (mounted) {
          setState(() => _step = _Step.email);
          _fadeCtrl.forward();
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Step 4: Success ─────────────────────────────────────────────────────────
  Widget _buildSuccessStep(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success icon
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  isDark
                      ? AppTheme.badgeGreenBgDark
                      : AppTheme.badgeGreenBgLight,
                  isDark ? const Color(0xFF0F2F1C) : const Color(0xFFE2F6E8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? const Color(0xFF1E5530)
                    : const Color(0xFFB8E2C4),
                width: 1.6,
              ),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF16A34A),
              size: 38,
            ),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          'Password Reset Successful',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),

        Text(
          'Your password has been successfully updated.\n'
          'You can now log in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white70 : const Color(0xFF777777),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 30),

        _GoldButton(
          label: 'Back to Login',
          isLoading: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.badgeRedBgDark : AppTheme.badgeRedBgLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF6B2530) : const Color(0xFFEFC2C2),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldButton extends StatelessWidget {
  final String label;
  final String loadingLabel;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _GoldButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
    this.loadingLabel = 'Please wait...',
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLoading
              ? [Colors.grey.shade400, Colors.grey.shade500]
              : [const Color(0xFFE2B04A), const Color(0xFFC89127)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: isLoading
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF694B0B),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    loadingLabel,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
      ),
    );
  }
}

class _BackLink extends StatelessWidget {
  final VoidCallback onTap;
  const _BackLink({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(
          Icons.arrow_back_rounded,
          size: 15,
          color: Color(0xFFD9A441),
        ),
        label: const Text(
          'Back to Login',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFFD9A441),
          ),
        ),
      ),
    );
  }
}
