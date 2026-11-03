class AppConstants {
  AppConstants._();

  static const String appName = 'DIU Ride';
  static const String appTagline = 'Daffodil Smart Commute';
  static const String proctorSecurityHelpline = '+8801711000000';
  static const String proctorExtension = 'Ext. 4410';

  // Storage Keys
  static const String tokenKey = 'diu_jwt_access_token';
  static const String refreshTokenKey = 'diu_jwt_refresh_token';
  static const String userKey = 'diu_cached_user';
  static const String onboardingKey = 'diu_onboarding_completed';

  // H3 Index Resolution
  static const int h3Resolution = 8; // ~460m hex size, ideal for campus & neighborhood matching

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
