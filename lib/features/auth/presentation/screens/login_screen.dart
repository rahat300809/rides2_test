import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/constants/app_colors.dart';
import 'package:diu_ride/core/theme/app_typography.dart';
import 'package:diu_ride/core/utils/validators.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/auth/presentation/screens/otp_screen.dart';
import 'package:diu_ride/features/auth/presentation/widgets/forgot_password_sheet.dart';
import 'package:diu_ride/shared/navigation/main_navigation_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Sign In Form State
  final _signInFormKey = GlobalKey<FormState>();
  final _loginIdentifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _obscureLoginPassword = true;
  bool _rememberMe = true;

  // Create Account Form State
  final _signUpFormKey = GlobalKey<FormState>();
  final _regNameController = TextEditingController();
  final _regStudentIdController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPhoneController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();
  bool _obscureRegPassword = true;
  bool _obscureConfirmPassword = true;
  String _detectedDept = '';
  String _detectedBatch = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(authNotifierProvider.notifier).clearError();
        setState(() {});
      }
    });

    _loadSavedLoginId();

    // Listen to Student ID for real-time department & batch display
    _regStudentIdController.addListener(() {
      final id = _regStudentIdController.text.trim();
      if (id.length >= 6) {
        setState(() {
          _detectedDept = Validators.getDepartmentName(id);
          _detectedBatch = Validators.getBatchName(id);
        });
      } else if (_detectedDept.isNotEmpty) {
        setState(() {
          _detectedDept = '';
          _detectedBatch = '';
        });
      }
    });
  }

  void _loadSavedLoginId() {
    try {
      final prefs = ref.read(preferencesProvider);
      final lastId = prefs.getLastLoginIdentifier();
      if (lastId != null && lastId.isNotEmpty) {
        _loginIdentifierController.text = lastId;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginIdentifierController.dispose();
    _loginPasswordController.dispose();
    _regNameController.dispose();
    _regStudentIdController.dispose();
    _regEmailController.dispose();
    _regPhoneController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  // --- Sign In Handler ---
  void _submitSignIn() async {
    if (!(_signInFormKey.currentState?.validate() ?? false)) return;

    final identifier = _loginIdentifierController.text.trim();
    final password = _loginPasswordController.text;

    final success = await ref
        .read(authNotifierProvider.notifier)
        .loginWithIdAndPassword(
          identifier: identifier,
          password: password,
        );

    if (success && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        (route) => false,
      );
    } else if (mounted) {
      final state = ref.read(authNotifierProvider);
      if (state.isOtpSent && state.pendingEmail != null) {
        // Direct option to verify now if email was not verified
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Your DIU email is not verified yet. Verification code sent!'),
            backgroundColor: AppColors.primary,
            action: SnackBarAction(
              label: 'Verify Now',
              textColor: Colors.white,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OtpScreen(
                      phone: '01712345678',
                      email: state.pendingEmail!,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }
    }
  }

  // --- Create Account Handler ---
  void _submitSignUp() async {
    if (!(_signUpFormKey.currentState?.validate() ?? false)) return;

    final name = _regNameController.text.trim();
    final studentId = _regStudentIdController.text.trim();
    final email = _regEmailController.text.trim();
    final phone = _regPhoneController.text.trim();
    final password = _regPasswordController.text;

    final success = await ref
        .read(authNotifierProvider.notifier)
        .registerWithDiuEmail(
          name: name,
          studentId: studentId,
          email: email,
          phone: phone,
          password: password,
        );

    if (success && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phone: phone,
            email: email,
          ),
        ),
      );
    }
  }


  // --- Open Forgot Password Dialog ---
  void _openForgotPassword() async {
    final identifier = _loginIdentifierController.text.trim();
    final resetId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ForgotPasswordSheet(
        initialIdentifier: identifier.isNotEmpty ? identifier : null,
      ),
    );

    if (resetId != null && resetId.isNotEmpty && mounted) {
      _loginIdentifierController.text = resetId;
      _loginPasswordController.clear();
      _tabController.animateTo(0);
    }
  }

  // --- Password Strength Calculation ---
  double _calculatePasswordStrength(String password) {
    if (password.isEmpty) return 0.0;
    double strength = 0.0;
    if (password.length >= 6) strength += 0.35;
    if (password.length >= 8) strength += 0.25;
    if (RegExp(r'[0-9]').hasMatch(password)) strength += 0.20;
    if (RegExp(r'[A-Za-z]').hasMatch(password) &&
        RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      strength += 0.20;
    }
    return strength.clamp(0.0, 1.0);
  }

  Color _getStrengthColor(double strength) {
    if (strength < 0.4) return AppColors.error;
    if (strength < 0.75) return AppColors.ratingStar;
    return AppColors.primary;
  }

  String _getStrengthText(double strength) {
    if (strength < 0.4) return 'Weak';
    if (strength < 0.75) return 'Medium';
    return 'Strong';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top App Logo
                Center(
                  child: Hero(
                    tag: 'diu_ride_logo',
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE65100).withOpacity(0.25),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(4),
                          child: Image.asset(
                            'assets/images/app_logo.png',
                            height: 72,
                            width: 72,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // DIU Verification Badge
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified, size: 16, color: AppColors.primary),
                        const SizedBox(width: 5),
                        Text(
                          'DIU Student Verified Commute',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Tab Switcher: Sign In vs Create Account
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: AppColors.onSurfaceVariant,
                    labelStyle: AppTypography.labelLg.copyWith(fontWeight: FontWeight.bold),
                    unselectedLabelStyle: AppTypography.labelLg,
                    tabs: const [
                      Tab(
                        height: 40,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login, size: 18),
                            SizedBox(width: 8),
                            Text('Sign In'),
                          ],
                        ),
                      ),
                      Tab(
                        height: 40,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_add_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('Create Account'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Error Message Banner (if any)
                if (authState.errorMessage != null && authState.errorMessage!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer.withOpacity(0.5),
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
                            style: AppTypography.bodySm.copyWith(
                              color: AppColors.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16, color: AppColors.error),
                          onPressed: () =>
                              ref.read(authNotifierProvider.notifier).clearError(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                // Tab Views
                AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    return _tabController.index == 0
                        ? _buildSignInTab(authState)
                        : _buildSignUpTab(authState);
                  },
                ),

                const SizedBox(height: 24),

                // Safety & Terms Notice
                Center(
                  child: Text(
                    'Exclusively for Daffodil International University students.\nPeer-to-peer fuel sharing with zero commercial commission.',
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: SIGN IN (Student ID + Password)
  // ==========================================
  Widget _buildSignInTab(AuthState authState) {
    return Form(
      key: _signInFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Student Sign In',
            style: AppTypography.headlineLg.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter your DIU Student ID or DIU Email and password.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // Student ID or University Email Field
          Text(
            'Student ID or DIU Email',
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _loginIdentifierController,
            validator: Validators.validateLoginIdentifier,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'e.g. 201-15-14285 or student@diu.edu.bd',
              prefixIcon: Icon(Icons.badge_outlined, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 16),

          // Password Field
          Text(
            'Password',
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _loginPasswordController,
            validator: Validators.validatePassword,
            obscureText: _obscureLoginPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitSignIn(),
            decoration: InputDecoration(
              hintText: 'Enter your password',
              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureLoginPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.outline,
                ),
                onPressed: () =>
                    setState(() => _obscureLoginPassword = !_obscureLoginPassword),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Remember Me & Forgot Password Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _rememberMe,
                    activeColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (val) => setState(() => _rememberMe = val ?? true),
                  ),
                  Text(
                    'Remember ID',
                    style: AppTypography.labelMd.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
              TextButton(
                onPressed: _openForgotPassword,
                child: Text(
                  'Forgot Password?',
                  style: AppTypography.labelMd.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sign In Submit Button
          ElevatedButton(
            onPressed: authState.isLoading ? null : _submitSignIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: authState.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Sign In with Password', style: AppTypography.labelLg),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          // Divider with "OR"
          Row(
            children: [
              Expanded(child: Divider(color: AppColors.outlineVariant.withOpacity(0.5))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR',
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.onSurfaceVariant.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(child: Divider(color: AppColors.outlineVariant.withOpacity(0.5))),
            ],
          ),
          const SizedBox(height: 14),

          // Explore as Guest / Trial App Button (Visitor Mode)
          OutlinedButton(
            onPressed: authState.isLoading
                ? null
                : () async {
                    final success = await ref.read(authNotifierProvider.notifier).loginAsGuest();
                    if (success && mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
                        (route) => false,
                      );
                    }
                  },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: AppColors.primary.withOpacity(0.04),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.explore_outlined, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Explore as Guest (App Trial)',
                  style: AppTypography.labelLg.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '👁️ Explore routes, campus radar & feeds in Visitor Mode',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.onSurfaceVariant.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: CREATE ACCOUNT (With DIU Email Verification)
  // ==========================================
  Widget _buildSignUpTab(AuthState authState) {
    final passwordStrength = _calculatePasswordStrength(_regPasswordController.text);

    return Form(
      key: _signUpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Create Student Account',
            style: AppTypography.headlineLg.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign up with your official DIU credentials. Verification code will be sent to your DIU email.',
            style: AppTypography.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // Full Name Field
          Text(
            'Full Name',
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _regNameController,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Please enter your full name' : null,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'e.g. Shakib Ahmed',
              prefixIcon: Icon(Icons.person_outline, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),

          // Student ID Field
          Text(
            'DIU Student ID',
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _regStudentIdController,
            validator: Validators.validateStudentId,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'e.g. 201-15-14285',
              prefixIcon: Icon(Icons.badge_outlined, color: AppColors.primary),
            ),
          ),

          // Dynamic Dept & Batch pill
          if (_detectedDept.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryFixed.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          '$_detectedDept • $_detectedBatch',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),

          // University Email Field
          Text(
            'Official DIU Email',
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _regEmailController,
            validator: Validators.validateDiuEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'e.g. student@diu.edu.bd',
              prefixIcon: Icon(Icons.alternate_email, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),

          // Mobile Number Field
          Text(
            'Mobile Number',
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _regPhoneController,
            validator: Validators.validatePhoneNumber,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: '017XXXXXXXX',
              prefixIcon: Icon(Icons.phone_android, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),

          // Password Field
          Text(
            'Create Password',
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _regPasswordController,
            validator: Validators.validatePassword,
            obscureText: _obscureRegPassword,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'At least 6 characters',
              prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureRegPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.outline,
                ),
                onPressed: () =>
                    setState(() => _obscureRegPassword = !_obscureRegPassword),
              ),
            ),
          ),

          // Password Strength Meter
          if (_regPasswordController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Password Strength:',
                        style: AppTypography.labelSm.copyWith(fontSize: 11),
                      ),
                      Text(
                        _getStrengthText(passwordStrength),
                        style: AppTypography.labelSm.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _getStrengthColor(passwordStrength),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: passwordStrength,
                      backgroundColor: AppColors.outlineVariant.withOpacity(0.3),
                      color: _getStrengthColor(passwordStrength),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),

          // Confirm Password Field
          Text(
            'Confirm Password',
            style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _regConfirmPasswordController,
            validator: (v) => Validators.validateConfirmPassword(
              v,
              _regPasswordController.text,
            ),
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submitSignUp(),
            decoration: InputDecoration(
              hintText: 'Re-enter your password',
              prefixIcon: const Icon(Icons.lock_reset, color: AppColors.primary),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.outline,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Create Account Submit Button
          ElevatedButton(
            onPressed: authState.isLoading ? null : _submitSignUp,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: authState.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onPrimary,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Create Account & Verify Email', style: AppTypography.labelLg),
                      const SizedBox(width: 8),
                      const Icon(Icons.mark_email_read_outlined, size: 18),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
