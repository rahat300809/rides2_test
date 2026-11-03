import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/services/firebase_auth_service.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/storage/secure_storage_service.dart';
import 'package:diu_ride/features/auth/data/models/user_model.dart';
import 'package:diu_ride/features/auth/data/repositories/auth_repository.dart';
import 'package:diu_ride/features/auth/data/repositories/mock_auth_repository.dart';

class SharedSyncAuthRepository implements AuthRepository {
  final SecureStorageService secureStorage;
  final PreferencesService preferences;
  late final MockAuthRepository _fallback;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  UserModel? _currentUser;

  SharedSyncAuthRepository({
    required this.secureStorage,
    required this.preferences,
  }) {
    _fallback = MockAuthRepository(
      secureStorage: secureStorage,
      preferences: preferences,
    );
  }

  String get _apiBase => AppConfig.current.apiBaseUrl;

  @override
  Future<UserModel> loginWithStudentId({
    required String name,
    required String studentId,
    required String email,
    required String phone,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanId = studentId.trim();
    final cleanName = name.trim().isNotEmpty ? name.trim() : 'DIU Student';

    try {
      final res = await _dio.post('$_apiBase/auth/login-student-id', data: {
        'name': cleanName,
        'studentId': cleanId,
        'email': cleanEmail,
        'phone': phone.trim(),
      });
      if (res.statusCode == 200 && res.data != null) {
        final user = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        await _persistUser(user);
        return user;
      }
    } catch (e) {
      debugPrint('SharedSyncAuth loginWithStudentId note: $e');
    }

    final user = await _fallback.loginWithStudentId(
      name: cleanName,
      studentId: cleanId,
      email: cleanEmail,
      phone: phone,
    );
    await _persistUser(user);
    return user;
  }

  @override
  Future<void> sendOtp(String phone) async {
    try {
      await _dio.post('$_apiBase/auth/send-otp', data: {'phone': phone});
    } catch (_) {}
  }

  @override
  Future<String> sendEmailOtp(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      await FirebaseAuthService.sendEmailVerification(email: cleanEmail);
    } catch (_) {}

    try {
      final res = await _dio.post('$_apiBase/auth/send-email-otp', data: {'email': cleanEmail});
      if (res.statusCode == 200 && res.data != null && res.data['otp'] != null) {
        final otp = res.data['otp'].toString();
        await preferences.saveLastGeneratedOtp(otp);
        return otp;
      }
    } catch (e) {
      debugPrint('Server send-email-otp note: $e');
    }
    return 'SENT';
  }

  @override
  Future<UserModel> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    return _fallback.verifyOtp(phone: phone, otp: otp);
  }

  @override
  Future<UserModel> verifyEmailOtp({
    required String email,
    required String otp,
    required String studentId,
    required String phone,
    String? name,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanId = studentId.trim();
    final studentName = (name != null && name.trim().isNotEmpty) ? name.trim() : 'DIU Student';

    try {
      final res = await _dio.post('$_apiBase/auth/verify-email', data: {
        'email': cleanEmail,
        'otp': otp,
        'studentId': cleanId,
        'phone': phone.trim(),
        'name': studentName,
      });
      if (res.statusCode == 200 && res.data != null && res.data['user'] != null) {
        final user = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        await _persistUser(user);
        return user;
      }
    } catch (e) {
      debugPrint('SharedSyncAuth verifyEmailOtp note: $e');
    }

    final user = await _fallback.verifyEmailOtp(
      email: cleanEmail,
      otp: otp,
      studentId: cleanId,
      phone: phone,
      name: studentName,
    );
    await _persistUser(user);
    return user;
  }

  @override
  Future<UserModel?> restoreSession() async {
    final cached = preferences.getUserJson();
    if (cached != null && cached.isNotEmpty) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        _currentUser = UserModel.fromJson(decoded);
        return _currentUser;
      } catch (e) {
        debugPrint('restoreSession error: $e');
      }
    }
    _currentUser = null;
    return null;
  }

  @override
  Future<void> logout() async {
    try {
      await _dio.post('$_apiBase/auth/logout');
    } catch (_) {}
    try {
      await secureStorage.clearTokens();
    } catch (_) {}
    try {
      await preferences.clearUser();
    } catch (_) {}
    try {
      await preferences.clearLastLoginIdentifier();
    } catch (_) {}
    try {
      await FirebaseAuthService.signOut();
    } catch (_) {}
    _currentUser = null;
  }

  @override
  Future<UserModel> updateProfile(UserModel updatedUser) async {
    try {
      await _dio.post('$_apiBase/auth/profile', data: updatedUser.toJson());
    } catch (_) {}
    await _persistUser(updatedUser);
    return updatedUser;
  }

  @override
  Future<UserModel> loginWithIdAndPassword({
    required String identifier,
    required String password,
  }) async {
    final cleanId = identifier.trim();

    try {
      final res = await _dio.post('$_apiBase/auth/login', data: {
        'identifier': cleanId,
        'password': password,
      });
      if (res.statusCode == 200 && res.data != null && res.data['user'] != null) {
        final user = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        if (res.data['token'] != null) {
          await secureStorage.saveTokens(
            accessToken: res.data['token'].toString(),
            refreshToken: res.data['refreshToken']?.toString() ?? '',
          );
        }
        await _persistUser(user);
        await preferences.saveLastLoginIdentifier(cleanId);
        await preferences.updateAccountPassword(user.studentId, password);
        await preferences.saveStudentAccount(
          studentId: user.studentId,
          email: user.email,
          password: password,
          userJson: jsonEncode(user.toJson()),
          isVerified: user.isDiuVerified,
          setActiveUser: true,
        );
        // Sync Firebase auth session in background if email available
        if (user.email.isNotEmpty) {
          FirebaseAuthService.signInWithEmailAndPassword(email: user.email, password: password).catchError((_) => null);
        }
        return user;
      }
    } catch (e) {
      debugPrint('Server login attempt error: $e');

      // Check if backend returned 401 (Incorrect password) with user email header / detail
      String? targetEmail;
      if (e is DioException) {
        final headers = e.response?.headers;
        targetEmail = headers?.value('X-User-Email') ?? headers?.value('x-user-email');
        if (targetEmail == null && e.response?.data is Map) {
          targetEmail = e.response?.data['email']?.toString();
        }
        if (targetEmail == null && cleanId.contains('@')) {
          targetEmail = cleanId.toLowerCase();
        }

        // If email was resolved, attempt verification with Firebase Auth directly!
        if (targetEmail != null && targetEmail.isNotEmpty) {
          debugPrint('[Login] Attempting Firebase Auth verification for $targetEmail...');
          final fbCred = await FirebaseAuthService.signInWithEmailAndPassword(
            email: targetEmail,
            password: password,
          );
          if (fbCred != null) {
            debugPrint('[Login] Firebase Auth verified! Syncing password with backend...');
            try {
              final syncRes = await _dio.post('$_apiBase/auth/login', data: {
                'identifier': cleanId,
                'password': password,
                'firebaseVerified': true,
              });
              if (syncRes.statusCode == 200 && syncRes.data != null && syncRes.data['user'] != null) {
                final user = UserModel.fromJson(Map<String, dynamic>.from(syncRes.data['user'] as Map));
                if (syncRes.data['token'] != null) {
                  await secureStorage.saveTokens(
                    accessToken: syncRes.data['token'].toString(),
                    refreshToken: syncRes.data['refreshToken']?.toString() ?? '',
                  );
                }
                await _persistUser(user);
                await preferences.saveLastLoginIdentifier(cleanId);
                return user;
              }
            } catch (syncErr) {
              debugPrint('[Login] Backend sync note: $syncErr');
            }
          }
        }

        final status = e.response?.statusCode;
        final detail = e.response?.data is Map ? e.response?.data['detail']?.toString() : null;
        if (status == 401) {
          throw Exception(detail ?? 'Incorrect password. Please verify and try again or use Forgot Password.');
        } else if (status == 403) {
          throw Exception(detail ?? 'Your account is not verified yet. Please check your DIU student email for the verification code.');
        } else if (status == 404) {
          throw Exception(detail ?? 'No student account found for "$cleanId". Please create an account.');
        } else if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }
      }
    }

    final user = await _fallback.loginWithIdAndPassword(
      identifier: identifier,
      password: password,
    );
    await _persistUser(user);
    await preferences.saveLastLoginIdentifier(cleanId);
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
    final cleanEmail = email.trim().toLowerCase();
    final cleanId = studentId.trim();
    final cleanName = name.trim();
    final cleanPhone = phone.trim();

    await preferences.clearPendingRegistration();

    final pendingMap = {
      'name': cleanName,
      'studentId': cleanId,
      'email': cleanEmail,
      'phone': cleanPhone,
      'password': password,
    };
    await preferences.savePendingRegistration(jsonEncode(pendingMap));

    // Dispatch official verification email to DIU student inbox via Firebase
    try {
      await FirebaseAuthService.dispatchVerificationEmail(
        email: cleanEmail,
        password: password,
      );
    } catch (e) {
      debugPrint('Firebase email dispatch note: $e');
    }

    try {
      final res = await _dio.post('$_apiBase/auth/register', data: pendingMap);
      if (res.statusCode == 200) {
        if (res.data != null && res.data['otp'] != null) {
          final serverOtp = res.data['otp'].toString();
          await preferences.saveLastGeneratedOtp(serverOtp);
        }
        return 'PENDING_EMAIL_VERIFICATION';
      }
    } on DioException catch (dioErr) {
      final msg = dioErr.response?.data is Map && dioErr.response?.data['detail'] != null
          ? dioErr.response?.data['detail'].toString()
          : 'Registration failed. Please verify your student information.';
      throw Exception(msg);
    } catch (e) {
      debugPrint('Server register note: $e');
      throw Exception('Failed to connect to authentication server. Please check internet connection.');
    }

    return 'PENDING_EMAIL_VERIFICATION';
  }

  @override
  Future<UserModel> verifyAndCompleteRegistration({
    required String otp,
  }) async {
    String pendingEmail = '';
    String pendingStudentId = '';

    final savedPending = preferences.getPendingRegistration();
    if (savedPending != null) {
      try {
        final decoded = jsonDecode(savedPending) as Map<String, dynamic>;
        pendingEmail = decoded['email'] as String? ?? '';
        pendingStudentId = decoded['studentId'] as String? ?? '';
      } catch (_) {}
    }

    // Check if student confirmed via Firebase verification link in email
    bool isFirebaseVerified = false;
    try {
      isFirebaseVerified = await FirebaseAuthService.isEmailVerified();
    } catch (_) {}

    try {
      final res = await _dio.post('$_apiBase/auth/verify-registration', data: {
        'email': pendingEmail,
        'studentId': pendingStudentId,
        'otp': otp.trim(),
        'firebaseVerified': isFirebaseVerified,
      });
      if (res.statusCode == 200 && res.data != null && res.data['user'] != null) {
        final user = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        await _persistUser(user);
        await preferences.clearPendingRegistration();
        return user;
      }
    } on DioException catch (dioErr) {
      final msg = dioErr.response?.data is Map && dioErr.response?.data['detail'] != null
          ? dioErr.response?.data['detail'].toString()
          : 'Invalid verification code. Please enter the valid code sent to your DIU email.';
      throw Exception(msg);
    } catch (e) {
      debugPrint('Server verify note: $e');
      if (e.toString().contains('Invalid verification code')) {
        rethrow;
      }
      throw Exception('Verification failed. Please check your DIU student email or click the Firebase link.');
    }

    throw Exception('Verification failed. Please enter the valid code sent to your email.');
  }

  @override
  Future<String> requestPasswordReset({
    required String identifier,
  }) async {
    final cleanId = identifier.trim();
    String? resolvedEmail = cleanId.contains('@') ? cleanId.toLowerCase() : null;
    String otp = 'SENT';
    bool backendSucceeded = false;

    // 1. Dispatch via Server Backend first to resolve student ID -> registered email & dispatch email OTP
    try {
      final res = await _dio.post('$_apiBase/auth/request-password-reset', data: {
        'identifier': cleanId,
      });
      if (res.statusCode == 200 && res.data != null) {
        backendSucceeded = true;
        otp = res.data['otp']?.toString() ?? 'SENT';
        final serverEmail = res.data['email']?.toString();
        if (serverEmail != null && serverEmail.isNotEmpty) {
          resolvedEmail = serverEmail.trim().toLowerCase();
          await preferences.saveResolvedResetEmail(resolvedEmail);
        }
        if (otp != 'SENT') {
          await preferences.saveLastGeneratedOtp(otp);
        }
      }
    } catch (e) {
      debugPrint('[Backend Reset] Error: $e');
      if (e is DioException && e.response?.data != null) {
        final detail = e.response?.data['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }
      }
    }

    // 2. Fallback to local storage if backend failed or offline
    if (!backendSucceeded) {
      try {
        final fallbackOtp = await _fallback.requestPasswordReset(identifier: identifier);
        otp = fallbackOtp;
        final savedEmail = preferences.getResolvedResetEmail();
        if (savedEmail != null && savedEmail.isNotEmpty) {
          resolvedEmail = savedEmail;
        }
      } catch (e) {
        debugPrint('[Fallback Reset] Error: $e');
      }
    }

    // 3. Dispatch Firebase password reset email to the RESOLVED registered email
    final targetEmail = resolvedEmail ?? (cleanId.contains('@') ? cleanId.toLowerCase() : '$cleanId@diu.edu.bd');
    await preferences.saveResolvedResetEmail(targetEmail);
    try {
      await FirebaseAuthService.sendPasswordResetEmail(targetEmail);
      debugPrint('[Firebase Reset] Dispatched Firebase password reset email to $targetEmail');
    } catch (e) {
      debugPrint('[Firebase Reset] Note: $e');
    }

    return otp;
  }

  @override
  Future<bool> verifyAndResetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
    final cleanId = identifier.trim();
    try {
      final res = await _dio.post('$_apiBase/auth/reset-password', data: {
        'identifier': cleanId,
        'otp': otp.trim(),
        'newPassword': newPassword,
      });
      if (res.statusCode == 200) {
        await preferences.updateAccountPassword(cleanId, newPassword);
        try {
          await _fallback.verifyAndResetPassword(
            identifier: identifier,
            otp: otp,
            newPassword: newPassword,
          );
        } catch (_) {}
        return true;
      }
    } catch (e) {
      debugPrint('[Backend Reset Password] Error: $e');
      if (e is DioException && e.response?.data is Map) {
        final detail = e.response?.data['detail']?.toString();
        if (detail != null && detail.isNotEmpty) {
          throw Exception(detail);
        }
      }
    }

    final fallbackResult = await _fallback.verifyAndResetPassword(
      identifier: identifier,
      otp: otp,
      newPassword: newPassword,
    );
    if (fallbackResult) {
      await preferences.updateAccountPassword(cleanId, newPassword);
    }
    return fallbackResult;
  }

  @override
  Future<UserModel> updateDefaultAddress(String address) async {
    final user = _currentUser ?? (await restoreSession());
    if (user == null) {
      throw Exception('Not authenticated');
    }
    try {
      final res = await _dio.post('$_apiBase/auth/default-address', data: {
        'userId': user.id,
        'studentId': user.studentId,
        'email': user.email,
        'defaultAddress': address,
      });
      if (res.statusCode == 200 && res.data != null && res.data['user'] != null) {
        final updated = UserModel.fromJson(Map<String, dynamic>.from(res.data['user'] as Map));
        await _persistUser(updated);
        return updated;
      }
    } catch (e) {
      debugPrint('Server default address update note: $e');
    }

    final updated = user.copyWith(defaultAddress: address);
    await _persistUser(updated);
    return updated;
  }

  Future<void> saveGuestSession(UserModel guest) async {
    await _persistUser(guest);
  }

  Future<void> _persistUser(UserModel user) async {
    _currentUser = user;
    final encoded = jsonEncode(user.toJson());
    await preferences.saveDedicatedAccount(user.studentId, encoded);
    await preferences.saveUserJson(encoded);
  }
}
