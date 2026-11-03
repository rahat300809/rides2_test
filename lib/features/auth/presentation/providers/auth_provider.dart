import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/storage/secure_storage_service.dart';
import 'package:diu_ride/features/auth/data/models/user_model.dart';
import 'package:diu_ride/features/auth/data/repositories/auth_repository.dart';
import 'package:diu_ride/features/auth/data/repositories/shared_sync_auth_repository.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final preferencesProvider = Provider<PreferencesService>((ref) {
  throw UnimplementedError('Initialize PreferencesService in main');
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final prefs = ref.watch(preferencesProvider);
  return SharedSyncAuthRepository(
    secureStorage: storage,
    preferences: prefs,
  );
});

class AuthState {
  final bool isLoading;
  final UserModel? user;
  final String? errorMessage;
  final bool isOtpSent;
  final String? pendingName;
  final String? pendingPhone;
  final String? pendingEmail;
  final String? pendingStudentId;
  final String? pendingPassword;
  final String? lastGeneratedOtp;
  final bool isPasswordResetSent;
  final String? resetIdentifier;
  final String? resetEmail;
  final String? resetOtp;

  const AuthState({
    this.isLoading = false,
    this.user,
    this.errorMessage,
    this.isOtpSent = false,
    this.pendingName,
    this.pendingPhone,
    this.pendingEmail,
    this.pendingStudentId,
    this.pendingPassword,
    this.lastGeneratedOtp,
    this.isPasswordResetSent = false,
    this.resetIdentifier,
    this.resetEmail,
    this.resetOtp,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    bool? isLoading,
    UserModel? user,
    String? errorMessage,
    bool? isOtpSent,
    String? pendingName,
    String? pendingPhone,
    String? pendingEmail,
    String? pendingStudentId,
    String? pendingPassword,
    String? lastGeneratedOtp,
    bool? isPasswordResetSent,
    String? resetIdentifier,
    String? resetEmail,
    String? resetOtp,
    bool clearError = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isOtpSent: isOtpSent ?? this.isOtpSent,
      pendingName: pendingName ?? this.pendingName,
      pendingPhone: pendingPhone ?? this.pendingPhone,
      pendingEmail: pendingEmail ?? this.pendingEmail,
      pendingStudentId: pendingStudentId ?? this.pendingStudentId,
      pendingPassword: pendingPassword ?? this.pendingPassword,
      lastGeneratedOtp: lastGeneratedOtp ?? this.lastGeneratedOtp,
      isPasswordResetSent: isPasswordResetSent ?? this.isPasswordResetSent,
      resetIdentifier: resetIdentifier ?? this.resetIdentifier,
      resetEmail: resetEmail ?? this.resetEmail,
      resetOtp: resetOtp ?? this.resetOtp,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final PreferencesService _preferences;

  AuthNotifier(this._repository, this._preferences) : super(const AuthState());

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  void setUser(UserModel? user) {
    state = state.copyWith(user: user);
  }

  Future<void> checkSession() async {
    state = state.copyWith(isLoading: true);
    try {
      final user = await _repository.restoreSession();
      state = state.copyWith(isLoading: false, user: user);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  // --- Student ID / Email + Password Login ---

  Future<bool> loginWithIdAndPassword({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.loginWithIdAndPassword(
        identifier: identifier,
        password: password,
      );
      state = state.copyWith(isLoading: false, user: user, clearError: true);
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.startsWith('DIU_EMAIL_NOT_VERIFIED:')) {
        final parts = msg.split(':');
        final email = parts.length > 1 ? parts[1] : '$identifier@diu.edu.bd';
        final otp = parts.length > 2 ? parts[2] : '123456';

        state = state.copyWith(
          isLoading: false,
          isOtpSent: true,
          pendingEmail: email,
          pendingStudentId: identifier,
          lastGeneratedOtp: otp,
          errorMessage: 'Please verify your DIU student email to complete account activation.',
        );
        return false;
      }

      state = state.copyWith(isLoading: false, errorMessage: msg);
      return false;
    }
  }

  // --- Register With DIU Email Verification ---

  Future<bool> registerWithDiuEmail({
    required String name,
    required String studentId,
    required String email,
    required String phone,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.registerWithDiuEmail(
        name: name,
        studentId: studentId,
        email: email,
        phone: phone,
        password: password,
      );

      String? cachedOtp;
      final repo = _repository;
      if (repo is SharedSyncAuthRepository) {
        cachedOtp = repo.preferences.getLastGeneratedOtp();
      }

      state = state.copyWith(
        isLoading: false,
        isOtpSent: true,
        pendingName: name,
        pendingStudentId: studentId,
        pendingEmail: email,
        pendingPhone: phone,
        pendingPassword: password,
        lastGeneratedOtp: cachedOtp,
        clearError: true,
      );
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, errorMessage: msg);
      return false;
    }
  }

  // --- Verify Registration Email Code ---

  Future<bool> verifyAndCompleteRegistration(String otp) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.verifyAndCompleteRegistration(otp: otp);
      state = state.copyWith(
        isLoading: false,
        user: user,
        isOtpSent: false,
        pendingName: null,
        pendingStudentId: null,
        pendingEmail: null,
        pendingPhone: null,
        pendingPassword: null,
        lastGeneratedOtp: null,
        clearError: true,
      );
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, errorMessage: msg);
      return false;
    }
  }

  // --- Password Reset Flow ---

  Future<bool> requestPasswordReset(String identifier) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final otp = await _repository.requestPasswordReset(identifier: identifier);
      final hasRealOtp = otp.isNotEmpty && otp != 'SENT';
      final resolvedEmail = _preferences.getResolvedResetEmail() ??
          (identifier.contains('@') ? identifier.toLowerCase() : '$identifier@diu.edu.bd');
      state = state.copyWith(
        isLoading: false,
        isPasswordResetSent: true,
        resetIdentifier: identifier,
        resetEmail: resolvedEmail,
        resetOtp: hasRealOtp ? otp : null,
        lastGeneratedOtp: hasRealOtp ? otp : null,
        clearError: true,
      );
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, errorMessage: msg);
      return false;
    }
  }

  Future<bool> verifyAndResetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.verifyAndResetPassword(
        identifier: identifier,
        otp: otp,
        newPassword: newPassword,
      );
      state = state.copyWith(
        isLoading: false,
        isPasswordResetSent: false,
        resetIdentifier: null,
        resetOtp: null,
        clearError: true,
      );
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, errorMessage: msg);
      return false;
    }
  }

  // --- Legacy Otp & Quick Login Support ---

  Future<bool> initiateLogin({
    required String name,
    required String studentId,
    required String email,
    required String phone,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.loginWithStudentId(
        name: name,
        studentId: studentId,
        email: email,
        phone: phone,
      );
      final otp = await _repository.sendEmailOtp(email);
      await _repository.sendOtp(phone);

      state = state.copyWith(
        isLoading: false,
        isOtpSent: true,
        pendingName: name,
        pendingPhone: phone,
        pendingEmail: email,
        pendingStudentId: studentId,
        lastGeneratedOtp: otp,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> verifyOtp(String otp) async {
    // If pending registration exists, delegate to verifyAndCompleteRegistration
    if (state.pendingPassword != null || state.isOtpSent || state.pendingEmail != null) {
      return await verifyAndCompleteRegistration(otp);
    }

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      UserModel user;
      final pendingEmail = state.pendingEmail;
      final pendingStudentId = state.pendingStudentId;
      final pendingPhone = state.pendingPhone;

      if (pendingEmail != null && pendingStudentId != null) {
        user = await _repository.verifyEmailOtp(
          name: state.pendingName,
          email: pendingEmail,
          otp: otp,
          studentId: pendingStudentId,
          phone: pendingPhone ?? '01712345678',
        );
      } else if (pendingPhone != null) {
        user = await _repository.verifyOtp(
          phone: pendingPhone,
          otp: otp,
        );
      } else {
        user = await _repository.verifyEmailOtp(
          name: state.pendingName ?? 'DIU Student',
          email: 'student@diu.edu.bd',
          otp: otp,
          studentId: '211-15-00000',
          phone: '01712345678',
        );
      }

      state = state.copyWith(isLoading: false, user: user, isOtpSent: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> resendEmailOtp() async {
    final pendingEmail = state.pendingEmail;
    if (pendingEmail == null) return;
    try {
      final newOtp = await _repository.sendEmailOtp(pendingEmail);
      final hasOtp = newOtp.isNotEmpty && newOtp != 'SENT';
      state = state.copyWith(lastGeneratedOtp: hasOtp ? newOtp : state.lastGeneratedOtp);
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<bool> updateDefaultAddress(String address) async {
    try {
      final updatedUser = await _repository.updateDefaultAddress(address);
      state = state.copyWith(user: updatedUser);
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _repository.logout();
    state = const AuthState();
  }

  Future<bool> loginAsGuest() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      const guest = UserModel(
        id: 'guest_visitor',
        studentId: 'VISITOR-GUEST',
        name: 'Guest Explorer',
        email: 'visitor@diu.edu.bd',
        phone: '01700000000',
        department: 'DIU Campus Visitor',
        batch: 'Trial Mode',
        isDiuVerified: false,
        role: UserRole.guest,
        rating: 5.0,
        isGuest: true,
      );
      final repo = _repository;
      if (repo is SharedSyncAuthRepository) {
        await repo.saveGuestSession(guest);
      }
      state = state.copyWith(isLoading: false, user: guest, clearError: true);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }
}

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final prefs = ref.watch(preferencesProvider);
  return AuthNotifier(repo, prefs);
});
