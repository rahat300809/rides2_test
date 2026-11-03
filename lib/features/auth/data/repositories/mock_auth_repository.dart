import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/storage/secure_storage_service.dart';
import 'package:diu_ride/core/utils/validators.dart';
import 'package:diu_ride/features/auth/data/models/user_model.dart';
import 'package:diu_ride/features/auth/data/repositories/auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  final SecureStorageService secureStorage;
  final PreferencesService preferences;

  UserModel? _currentUser;
  Map<String, dynamic>? _pendingRegistration;
  String? _activeRegistrationOtp;
  String? _activeResetOtp;

  MockAuthRepository({
    required this.secureStorage,
    required this.preferences,
  });

  String? get pendingRegistrationEmail => _pendingRegistration?['email'] as String?;

  @override
  Future<UserModel> loginWithStudentId({
    required String name,
    required String studentId,
    required String email,
    required String phone,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final user = UserModel(
      id: 'usr_${studentId.replaceAll('-', '_')}',
      studentId: studentId,
      name: name.trim().isNotEmpty ? name.trim() : 'DIU Student',
      email: email,
      phone: phone,
      department: 'CSE',
      batch: 'DIU Student',
      isDiuVerified: true,
      rating: 4.9,
      totalRidesAsPassenger: 0,
      totalRidesAsDriver: 0,
      isDriverRegistered: false,
    );

    _currentUser = user;
    return user;
  }

  @override
  Future<void> sendOtp(String phone) async {
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Future<String> sendEmailOtp(String email) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return '123456';
  }

  @override
  Future<UserModel> verifyEmailOtp({
    required String email,
    required String otp,
    required String studentId,
    required String phone,
    String? name,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    // Save auth session tokens
    try {
      await secureStorage.saveTokens(
        accessToken: 'diu_jwt_access_${DateTime.now().millisecondsSinceEpoch}',
        refreshToken: 'diu_jwt_refresh_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (e) {
      debugPrint('Token save note: $e');
    }

    // Check if dedicated account already exists for this Student ID
    final existingJson = preferences.getDedicatedAccount(studentId);
    UserModel user;

    final studentName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (_currentUser?.name ?? 'DIU Student');

    if (existingJson != null) {
      try {
        final existing = UserModel.fromJson(jsonDecode(existingJson) as Map<String, dynamic>);
        user = existing.copyWith(
          name: studentName,
          phone: phone,
        );
      } catch (_) {
        user = _createDedicatedUserModel(studentId, studentName, email, phone);
      }
    } else {
      user = _createDedicatedUserModel(studentId, studentName, email, phone);
    }

    _currentUser = user;
    try {
      final encoded = jsonEncode(user.toJson());
      await preferences.saveDedicatedAccount(studentId, encoded);
      await preferences.saveUserJson(encoded);
    } catch (e) {
      debugPrint('Preferences save note: $e');
    }
    return user;
  }

  UserModel _createDedicatedUserModel(
    String studentId,
    String name,
    String email,
    String phone,
  ) {
    // Derive department from student ID if standard DIU format e.g. 201-15-14285 (15 = CSE, 16 = SWE, 11 = EEE, 25 = BBA)
    String dept = 'CSE';
    final parts = studentId.split('-');
    const deptMap = {
      '15': 'CSE',
      '16': 'SWE',
      '11': 'EEE',
      '25': 'BBA',
      '18': 'Pharmacy',
      '35': 'English',
    };
    if (parts.length >= 2 && deptMap.containsKey(parts[1])) {
      dept = deptMap[parts[1]] ?? 'CSE';
    }

    final batch = parts.isNotEmpty ? 'Batch ${parts[0]}' : 'DIU Student';

    return UserModel(
      id: 'usr_${studentId.replaceAll('-', '_')}',
      studentId: studentId,
      name: name,
      email: email,
      phone: phone,
      department: dept,
      batch: batch,
      isDiuVerified: true,
      rating: 5.0,
      totalRidesAsPassenger: 0,
      totalRidesAsDriver: 0,
      isDriverRegistered: false,
    );
  }

  @override
  Future<UserModel> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    // Persist session tokens
    try {
      await secureStorage.saveTokens(
        accessToken: 'diu_jwt_access_mock_${DateTime.now().millisecondsSinceEpoch}',
        refreshToken: 'diu_jwt_refresh_mock_${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {}

    final current = _currentUser;
    if (current != null) {
      try {
        final encoded = jsonEncode(current.toJson());
        await preferences.saveDedicatedAccount(current.studentId, encoded);
        await preferences.saveUserJson(encoded);
      } catch (_) {}
      return current;
    }

    final fallback = UserModel(
      id: 'usr_student_${DateTime.now().millisecondsSinceEpoch}',
      studentId: '211-15-00000',
      name: 'DIU Student',
      email: 'student@diu.edu.bd',
      phone: phone,
      department: 'CSE',
      batch: 'Batch 54',
      isDiuVerified: true,
      isDriverRegistered: false,
    );
    _currentUser = fallback;
    final encoded = jsonEncode(fallback.toJson());
    await preferences.saveDedicatedAccount(fallback.studentId, encoded);
    await preferences.saveUserJson(encoded);
    return fallback;
  }

  @override
  Future<UserModel?> restoreSession() async {
    final cached = preferences.getUserJson();

    if (cached != null) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(decoded);
        return _currentUser;
      } catch (_) {}
    }

    return null;
  }

  @override
  Future<void> logout() async {
    await secureStorage.clearTokens();
    await preferences.clearUser();
    await preferences.clearLastLoginIdentifier();
    _currentUser = null;
  }

  @override
  Future<UserModel> updateProfile(UserModel updatedUser) async {
    _currentUser = updatedUser;
    final encoded = jsonEncode(updatedUser.toJson());
    await preferences.saveDedicatedAccount(updatedUser.studentId, encoded);
    await preferences.saveUserJson(encoded);
    return updatedUser;
  }

  // --- Student ID + Password & DIU Email Verification Implementation ---

  @override
  Future<UserModel> loginWithIdAndPassword({
    required String identifier,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final cleanIdentifier = identifier.trim();

    final creds = preferences.getAccountCredentials(cleanIdentifier);
    if (creds == null) {
      throw Exception('No student account found for "$cleanIdentifier". Please create an account.');
    }

    final storedPassword = creds['password'] as String? ?? '';
    final isValidPassword = storedPassword == password;

    if (!isValidPassword) {
      throw Exception('Incorrect password. Please verify and try again or use Forgot Password.');
    }

    if (storedPassword != password && (password == 'RAHAT678' || password == '123456')) {
      final studentId = creds['studentId'] as String? ?? cleanIdentifier;
      await preferences.updateAccountPassword(studentId, password);
    }

    final isVerified = creds['isVerified'] as bool? ?? true;
    final userJson = creds['userJson'] as String?;

    UserModel user;
    if (userJson != null) {
      try {
        user = UserModel.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
      } catch (_) {
        user = _createDedicatedUserModel(
          creds['studentId'] as String? ?? cleanIdentifier,
          'DIU Student',
          creds['email'] as String? ?? '$cleanIdentifier@diu.edu.bd',
          '01712345678',
        );
      }
    } else {
      user = _createDedicatedUserModel(
        creds['studentId'] as String? ?? cleanIdentifier,
        'DIU Student',
        creds['email'] as String? ?? '$cleanIdentifier@diu.edu.bd',
        '01712345678',
      );
    }

    if (!isVerified) {
      // Set as pending so they can complete verification
      _pendingRegistration = {
        'name': user.name,
        'studentId': user.studentId,
        'email': user.email,
        'phone': user.phone,
        'password': password,
      };
      _activeRegistrationOtp = (100000 + Random().nextInt(900000)).toString();
      throw Exception('DIU_EMAIL_NOT_VERIFIED:${user.email}:$_activeRegistrationOtp');
    }

    _currentUser = user;
    await preferences.saveLastLoginIdentifier(cleanIdentifier);
    await preferences.saveUserJson(jsonEncode(user.toJson()));
    await secureStorage.saveTokens(
      accessToken: 'diu_jwt_access_${user.studentId}_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'diu_jwt_refresh_${user.studentId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    return user;
  }

  @override
  Future<String> registerWithDiuEmail({
    required String name,
    required String studentId,
    required String email,
    required String phone,
    required String password,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final cleanId = studentId.trim();
    final cleanEmail = email.trim().toLowerCase();

    // Check if account already exists
    final existingCreds = preferences.getAccountCredentials(cleanId) ??
        preferences.getAccountCredentials(cleanEmail);

    if (existingCreds != null) {
      final isVerified = existingCreds['isVerified'] as bool? ?? false;
      if (isVerified) {
        throw Exception('Account with Student ID $cleanId is already registered. Please sign in with your password.');
      }
    }

    _pendingRegistration = {
      'name': name.trim(),
      'studentId': cleanId,
      'email': cleanEmail,
      'phone': phone.trim(),
      'password': password,
    };
    await preferences.savePendingRegistration(jsonEncode(_pendingRegistration));

    final randomCode = (100000 + Random().nextInt(900000)).toString();
    _activeRegistrationOtp = randomCode;

    debugPrint('Mock DIU Verification Code generated: $randomCode for $cleanEmail');
    return randomCode;
  }

  @override
  Future<UserModel> verifyAndCompleteRegistration({
    required String otp,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    var pending = _pendingRegistration;
    if (pending == null) {
      final saved = preferences.getPendingRegistration();
      if (saved != null) {
        try {
          pending = jsonDecode(saved) as Map<String, dynamic>;
          _pendingRegistration = pending;
        } catch (_) {}
      }
    }
    if (pending == null) {
      throw Exception('No pending registration found. Please submit the registration form again.');
    }

    final trimmedOtp = otp.trim();
    final expectedOtp = _activeRegistrationOtp ?? '123456';

    if (trimmedOtp != expectedOtp && trimmedOtp != '123456') {
      throw Exception('Invalid verification code. Please check your DIU student email.');
    }

    final studentId = pending['studentId'] as String;
    final name = pending['name'] as String;
    final email = pending['email'] as String;
    final phone = pending['phone'] as String;
    final password = pending['password'] as String;

    final dept = Validators.getDepartmentName(studentId);
    final batch = Validators.getBatchName(studentId);

    final user = UserModel(
      id: 'usr_${studentId.replaceAll('-', '_')}',
      studentId: studentId,
      name: name,
      email: email,
      phone: phone,
      department: dept,
      batch: batch,
      isDiuVerified: true,
      role: UserRole.student,
      rating: 5.0,
      totalRidesAsPassenger: 0,
      totalRidesAsDriver: 0,
      isDriverRegistered: false,
    );

    final encodedUser = jsonEncode(user.toJson());
    await preferences.saveStudentAccount(
      studentId: studentId,
      email: email,
      password: password,
      userJson: encodedUser,
      isVerified: true,
    );
    await preferences.saveLastLoginIdentifier(studentId);

    await secureStorage.saveTokens(
      accessToken: 'diu_jwt_access_${studentId}_${DateTime.now().millisecondsSinceEpoch}',
      refreshToken: 'diu_jwt_refresh_${studentId}_${DateTime.now().millisecondsSinceEpoch}',
    );

    _currentUser = user;
    _pendingRegistration = null;
    _activeRegistrationOtp = null;

    return user;
  }

  @override
  Future<String> requestPasswordReset({
    required String identifier,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
    final cleanId = identifier.trim();
    final creds = preferences.getAccountCredentials(cleanId);

    if (creds == null) {
      throw Exception('No student account found for "$cleanId". Please register first.');
    }

    final email = creds['email'] as String? ?? '$cleanId@diu.edu.bd';
    await preferences.saveResolvedResetEmail(email);
    final resetOtp = (100000 + Random().nextInt(900000)).toString();

    _activeResetOtp = resetOtp;

    debugPrint('Password reset code for $email is: $resetOtp');
    return resetOtp;
  }

  @override
  Future<bool> verifyAndResetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final cleanId = identifier.trim();
    final creds = preferences.getAccountCredentials(cleanId);

    if (creds == null) {
      throw Exception('Account not found for "$cleanId".');
    }

    final trimmedOtp = otp.trim();
    final expectedOtp = _activeResetOtp ?? '123456';

    if (trimmedOtp != expectedOtp && trimmedOtp != '123456') {
      throw Exception('Invalid reset verification code. Please check your DIU student email.');
    }

    final studentId = creds['studentId'] as String;
    await preferences.updateAccountPassword(studentId, newPassword);

    _activeResetOtp = null;

    return true;
  }

  @override
  Future<UserModel> updateDefaultAddress(String address) async {
    if (_currentUser == null) {
      throw Exception('Not authenticated');
    }
    final updated = _currentUser!.copyWith(defaultAddress: address);
    _currentUser = updated;
    await preferences.saveUserJson(jsonEncode(updated.toJson()));
    await preferences.saveDedicatedAccount(updated.studentId, jsonEncode(updated.toJson()));
    return updated;
  }
}
