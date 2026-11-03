import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/validators.dart';
import 'package:diu_ride/core/services/firebase_auth_service.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/webview/presentation/screens/campus_webview_screen.dart';
import 'package:diu_ride/shared/navigation/main_navigation_screen.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String phone;
  final String email;

  const OtpScreen({
    super.key,
    required this.phone,
    required this.email,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  int _resendCountdown = 45;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendCountdown = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() => _resendCountdown--);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _verify() async {
    if (_formKey.currentState?.validate() ?? false) {
      final success = await ref.read(authNotifierProvider.notifier).verifyOtp(
            _otpController.text.trim(),
          );
      if (success && mounted) {
        final user = ref.read(authNotifierProvider).user;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const Icon(Icons.verified_user, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Dedicated account activated for ${user?.studentId ?? ''}!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
          (route) => false,
        );
      }
    }
  }

  void _checkFirebaseVerification() async {
    final verified = await FirebaseAuthService.isEmailVerified();
    if (verified) {
      final success = await ref.read(authNotifierProvider.notifier).verifyOtp('FIREBASE_VERIFIED');
      if (success && mounted) {
        final user = ref.read(authNotifierProvider).user;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Row(
              children: [
                const Icon(Icons.verified_user, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Firebase email verified! Account activated for ${user?.studentId ?? ''}!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
          (route) => false,
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firebase verification link not clicked yet. Please click the link sent to your DIU student email or enter the 6-digit code.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _resend() async {
    if (_resendCountdown == 0) {
      await ref.read(authNotifierProvider.notifier).resendEmailOtp();
      _startTimer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('New verification code sent to ${widget.email}'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    }
  }

  void _openGmail() async {
    final launched = await FirebaseAuthService.openGmailInbox(email: widget.email);
    if (!launched && mounted) {
      _openWebmail();
    }
  }

  void _resendFirebaseEmail() async {
    // Re-dispatch through both client Firebase SDK and backend Firebase Identity Toolkit
    try {
      await FirebaseAuthService.sendEmailVerification(email: widget.email);
    } catch (_) {}
    await ref.read(authNotifierProvider.notifier).resendEmailOtp();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Firebase verification email re-sent to ${widget.email}. Please check your Inbox and Spam/Junk folder.'),
          backgroundColor: AppColors.primary,
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Security Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryFixed.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mark_email_read, size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'DIU Email Verification',
                            style: AppTypography.labelSm.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Text(
                  'Verify Your Student Account',
                  style: AppTypography.headlineLg.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                RichText(
                  text: TextSpan(
                    style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                    children: [
                      const TextSpan(text: 'We sent a verification code to your official DIU email: '),
                      TextSpan(
                        text: widget.email,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(text: ' and phone '),
                      TextSpan(
                        text: widget.phone,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: '. Enter the code to activate your account.'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.mark_email_read, size: 20, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Firebase Verification Email Dispatched',
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A verification link has been sent to ${widget.email}. Open your DIU student email inbox (or spam folder) and click the link.',
                        style: AppTypography.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        onPressed: _checkFirebaseVerification,
                        icon: const Icon(Icons.verified, size: 18),
                        label: const Text('I Clicked Verification Link in Email'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _openGmail,
                        icon: const Icon(Icons.mail_outline, size: 16),
                        label: const Text('Open DIU Webmail / Gmail (Check Spam)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1B5E20),
                          side: const BorderSide(color: Color(0xFF81C784)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),

                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'OR ENTER 6-DIGIT CODE',
                        style: AppTypography.labelSm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 14),

                // OTP input
                TextFormField(
                  controller: _otpController,
                  validator: Validators.validateOtp,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: AppTypography.display.copyWith(
                    letterSpacing: 12,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••••',
                    hintStyle: AppTypography.display.copyWith(
                      letterSpacing: 12,
                      fontSize: 28,
                      color: AppColors.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (authState.errorMessage != null && authState.errorMessage!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      authState.errorMessage ?? '',
                      style: AppTypography.bodySm.copyWith(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // Submit Button
                ElevatedButton(
                  onPressed: authState.isLoading ? null : _verify,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Verify & Enter Campus'),
                ),
                const SizedBox(height: 16),

                // Resend Timer Button
                TextButton.icon(
                  onPressed: _resendCountdown == 0 ? _resend : null,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    _resendCountdown == 0
                        ? 'Resend Verification Code'
                        : 'Resend Code in ${_resendCountdown}s',
                    style: AppTypography.labelLg.copyWith(
                      color: _resendCountdown == 0
                          ? AppColors.primary
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _resendFirebaseEmail,
                  icon: const Icon(Icons.send_outlined, size: 16, color: AppColors.primary),
                  label: const Text('Resend Firebase Verification Link to Email'),
                ),

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Quick Link to Gmail & DIU Student Webmail
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _openGmail,
                        icon: const Icon(Icons.mail, size: 16),
                        label: const Text('Open Gmail'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEA4335), // Google Red
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openWebmail,
                        icon: const Icon(Icons.school, size: 16),
                        label: const Text('DIU Webmail'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
