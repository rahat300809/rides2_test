import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/validators.dart';
import 'package:diu_ride/core/services/firebase_auth_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/webview/presentation/screens/campus_webview_screen.dart';

class ForgotPasswordSheet extends ConsumerStatefulWidget {
  final String? initialIdentifier;

  const ForgotPasswordSheet({
    super.key,
    this.initialIdentifier,
  });

  @override
  ConsumerState<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<ForgotPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  late final TextEditingController _identifierController;
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _linkSent = false;
  String? _dispatchedEmail;
  String? _studentName;
  bool _obscureNewPass = true;
  bool _obscureConfirmPass = true;
  bool _isResetting = false;

  @override
  void initState() {
    super.initState();
    _identifierController = TextEditingController(text: widget.initialIdentifier ?? '');
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _requestResetLink() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final identifier = _identifierController.text.trim();
    final success = await ref
        .read(authNotifierProvider.notifier)
        .requestPasswordReset(identifier);

    if (success && mounted) {
      String resolved = ref.read(authNotifierProvider).resetEmail ??
          (identifier.contains('@') ? identifier.toLowerCase() : '$identifier@diu.edu.bd');

      setState(() {
        _linkSent = true;
        _dispatchedEmail = resolved;
        _studentName = identifier.split('@')[0];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification code & reset link dispatched to: $resolved'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (mounted) {
      final errorMsg = ref.read(authNotifierProvider).errorMessage ??
          'Unable to send reset code. Please verify your Student ID or Email.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _submitResetWithOtp() async {
    if (!(_resetFormKey.currentState?.validate() ?? false)) return;

    final p1 = _newPasswordController.text.trim();
    final p2 = _confirmPasswordController.text.trim();
    if (p1 != p2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Passwords do not match. Please re-enter.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isResetting = true);
    final identifier = _identifierController.text.trim();
    final otp = _otpController.text.trim();

    final success = await ref.read(authNotifierProvider.notifier).verifyAndResetPassword(
      identifier: identifier,
      otp: otp,
      newPassword: p1,
    );

    if (success && mounted) {
      // Auto login with the new password
      final loginSuccess = await ref.read(authNotifierProvider.notifier).loginWithIdAndPassword(
        identifier: identifier,
        password: p1,
      );

      if (mounted) {
        setState(() => _isResetting = false);
        if (loginSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password updated successfully! Welcome back.'),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password updated! Please sign in with your new password.'),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pop(identifier);
        }
      }
    } else if (mounted) {
      setState(() => _isResetting = false);
      final errorMsg = ref.read(authNotifierProvider).errorMessage ??
          'Failed to reset password. Please check your 6-digit verification code.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openWebmail() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CampusWebViewScreen(
          title: 'DIU Student Webmail',
          initialUrl: 'https://mail.google.com/a/diu.edu.bd',
        ),
      ),
    );
  }

  void _openGmail() async {
    final launched = await FirebaseAuthService.openGmailInbox(email: _dispatchedEmail);
    if (!launched && mounted) {
      _openWebmail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryFixed.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _linkSent ? Icons.mark_email_read_outlined : Icons.lock_reset,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _linkSent ? 'Reset Your Password' : 'Forgot Password?',
                        style: AppTypography.headlineSm.copyWith(
                          color: AppColors.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _linkSent
                            ? 'Enter verification code or check email'
                            : 'Recover your DIU student account',
                        style: AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.onSurfaceVariant),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (authState.errorMessage != null && !_linkSent)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        authState.errorMessage!,
                        style: AppTypography.bodySm.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),

            // ==========================================
            // STEP 1: Enter ID / Email
            // ==========================================
            if (!_linkSent)
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'DIU Student ID or University Email',
                      style: AppTypography.labelMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _identifierController,
                      validator: Validators.validateLoginIdentifier,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _requestResetLink(),
                      decoration: const InputDecoration(
                        hintText: 'e.g. 252-15-234 or student@diu.edu.bd',
                        prefixIcon: Icon(Icons.badge_outlined, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enter your student ID or email. We will automatically resolve your registered DIU email and send a 6-digit verification code.',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: authState.isLoading ? null : _requestResetLink,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: authState.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send_rounded, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Send Verification Code & Link',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              )
            else
              // ==========================================
              // STEP 2: In-App Code Entry & Direct Link
              // ==========================================
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Greeting & Confirmation Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFE65100).withOpacity(0.08),
                          const Color(0xFFF57C00).withOpacity(0.03),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE65100).withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.waving_hand, color: Color(0xFFE65100), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Hello, ${_studentName ?? "DIU Student"}!',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A 6-digit verification code & reset link was sent to:',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.3),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.email_outlined, color: Color(0xFFE65100), size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _dispatchedEmail ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Option A: In-App Reset Form
                  Form(
                    key: _resetFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '6-Digit Verification Code (from Email)',
                          style: AppTypography.labelMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          validator: (v) {
                            if (v == null || v.trim().length < 6) {
                              return 'Please enter the 6-digit code sent to your email';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            hintText: 'e.g. 724888',
                            counterText: '',
                            prefixIcon: Icon(Icons.pin_outlined, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Text(
                          'New Password',
                          style: AppTypography.labelMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscureNewPass,
                          validator: (v) {
                            if (v == null || v.trim().length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Enter new password (min 6 chars)',
                            prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureNewPass ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscureNewPass = !_obscureNewPass),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Text(
                          'Confirm New Password',
                          style: AppTypography.labelMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPass,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Please re-enter your new password';
                            }
                            return null;
                          },
                          decoration: InputDecoration(
                            hintText: 'Re-enter new password',
                            prefixIcon: const Icon(Icons.lock_reset, color: AppColors.primary),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirmPass ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        ElevatedButton(
                          onPressed: _isResetting ? null : _submitResetWithOtp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isResetting
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Set New Password & Sign In',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text('OR', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Open Gmail / Webmail Primary Button
                  OutlinedButton.icon(
                    onPressed: _openGmail,
                    icon: const Icon(Icons.mail_outline, size: 18),
                    label: const Text(
                      'Open Gmail / DIU Webmail',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE65100),
                      side: const BorderSide(color: Color(0xFFE65100)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Resend link button
                  Center(
                    child: TextButton.icon(
                      onPressed: authState.isLoading ? null : _requestResetLink,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Didn\'t receive code? Tap to resend', style: TextStyle(fontSize: 12.5)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
