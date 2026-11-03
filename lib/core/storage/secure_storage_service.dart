import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:diu_ride/core/constants/app_constants.dart';

class SecureStorageService {
  final FlutterSecureStorage _storage;
  static final Map<String, String> _memStorage = {};

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              webOptions: WebOptions(
                dbName: 'diu_ride_secure',
                publicKey: 'diu_ride_key',
              ),
            );

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _memStorage[AppConstants.tokenKey] = accessToken;
    _memStorage[AppConstants.refreshTokenKey] = refreshToken;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.tokenKey, accessToken);
      await prefs.setString(AppConstants.refreshTokenKey, refreshToken);
    } catch (_) {}

    try {
      await _storage.write(key: AppConstants.tokenKey, value: accessToken);
      await _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken);
    } catch (e) {
      debugPrint('SecureStorageService write note (using prefs/memory fallback): $e');
    }
  }

  Future<String?> getAccessToken() async {
    try {
      final val = await _storage.read(key: AppConstants.tokenKey);
      if (val != null && val.isNotEmpty) return val;
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(AppConstants.tokenKey);
      if (val != null && val.isNotEmpty) return val;
    } catch (_) {}

    return _memStorage[AppConstants.tokenKey];
  }

  Future<String?> getRefreshToken() async {
    try {
      final val = await _storage.read(key: AppConstants.refreshTokenKey);
      if (val != null && val.isNotEmpty) return val;
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(AppConstants.refreshTokenKey);
      if (val != null && val.isNotEmpty) return val;
    } catch (_) {}

    return _memStorage[AppConstants.refreshTokenKey];
  }

  Future<void> clearTokens() async {
    _memStorage.remove(AppConstants.tokenKey);
    _memStorage.remove(AppConstants.refreshTokenKey);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.tokenKey);
      await prefs.remove(AppConstants.refreshTokenKey);
    } catch (_) {}

    try {
      await _storage.delete(key: AppConstants.tokenKey);
      await _storage.delete(key: AppConstants.refreshTokenKey);
    } catch (_) {}
  }
}
