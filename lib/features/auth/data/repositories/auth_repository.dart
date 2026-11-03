import 'package:diu_ride/features/auth/data/models/user_model.dart';

abstract class AuthRepository {
  Future<UserModel> loginWithStudentId({
    required String name,
    required String studentId,
    required String email,
    required String phone,
  });

  Future<void> sendOtp(String phone);

  Future<String> sendEmailOtp(String email);

  Future<UserModel> verifyOtp({
    required String phone,
    required String otp,
  });

  Future<UserModel> verifyEmailOtp({
    required String email,
    required String otp,
    required String studentId,
    required String phone,
    String? name,
  });

  Future<UserModel?> restoreSession();

  Future<void> logout();

  Future<UserModel> updateProfile(UserModel updatedUser);

  // --- Student ID + Password & DIU Email Verification ---

  Future<UserModel> loginWithIdAndPassword({
    required String identifier,
    required String password,
  });

  Future<String> registerWithDiuEmail({
    required String name,
    required String studentId,
    required String email,
    required String phone,
    required String password,
  });

  Future<UserModel> verifyAndCompleteRegistration({
    required String otp,
  });

  Future<String> requestPasswordReset({
    required String identifier,
  });

  Future<bool> verifyAndResetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  });

  Future<UserModel> updateDefaultAddress(String address);
}
