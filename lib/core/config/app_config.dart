import 'package:flutter/foundation.dart';

enum Environment { development, staging, production }

class AppConfig {
  final Environment environment;
  final String apiBaseUrl;
  final String wsBaseUrl;
  final String googleMapsApiKey;
  final bool useMockData;

  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.googleMapsApiKey,
    this.useMockData = false,
  });

  static late AppConfig current;

  static void initialize({
    Environment environment = Environment.production,
    String? apiBaseUrl,
    String? wsBaseUrl,
    String? googleMapsApiKey,
    bool useMockData = false,
  }) {
    current = AppConfig(
      environment: environment,
      apiBaseUrl: apiBaseUrl ?? defaultApiUrl,
      wsBaseUrl: wsBaseUrl ?? defaultWsUrl,
      googleMapsApiKey: googleMapsApiKey ?? 'AIzaSyD-hl4Vshm6lqgUopu4rHbwmUbbPNA7kfA',
      useMockData: useMockData,
    );
  }

  static String get defaultApiUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.startsWith('http://localhost') || origin.startsWith('http://127.0.0.1')) {
        return 'http://127.0.0.1:8080/ride/api';
      }
      return '$origin/ride/api';
    }
    // Mobile points directly to the production Ubuntu server
    return 'https://servertest.eu.cc/ride/api';
  }

  static String get fallbackApiUrl {
    return 'https://servertest.eu.cc/ride/api';
  }

  static String get defaultWsUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'ws://127.0.0.1:8080/ride/ws';
      }
      final portStr = Uri.base.hasPort ? ':${Uri.base.port}' : '';
      final isSecure = Uri.base.scheme == 'https';
      final scheme = isSecure ? 'wss://' : 'ws://';
      return '$scheme$host$portStr/ride/ws';
    }
    return 'wss://servertest.eu.cc/ride/ws';
  }

  static String get fallbackWsUrl {
    return 'wss://servertest.eu.cc/ride/ws';
  }
}
