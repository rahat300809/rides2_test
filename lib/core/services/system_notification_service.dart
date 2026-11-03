import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'system_notification_stub.dart'
    if (dart.library.html) 'system_notification_web.dart';

/// Unified System Notification Service:
/// 1. Posts to Android Mobile Notification Bar (Heads-up / Status bar with channel & vibration)
/// 2. Posts to Web Browser System Notification Bar (Chrome, Edge, Firefox, Safari)
/// 3. Emits terminal audit logs for verification
class SystemNotificationService {
  static const MethodChannel _channel = MethodChannel('com.diu.ride/notifications');

  /// Initialize and request notification permission on app startup
  static Future<void> initialize() async {
    if (kIsWeb) {
      requestWebNotificationPermission();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('requestPermission');
      } catch (e) {
        debugPrint('[SYSTEM_NOTIFICATION_PERMISSION ERROR] $e');
      }
    }
  }

  /// Triggers a real native system notification on Mobile phone status bar OR Web browser tray
  static Future<void> showNotification({
    required String title,
    required String body,
    String? id,
  }) async {
    // 1. Production Terminal Log for audit verification
    // ignore: avoid_print
    print('[DIU_NOTIFICATION_BAR] $title: $body');

    // 2. Invoke Web browser native notification if on Web
    if (kIsWeb) {
      triggerWebNotification(title, body, id);
      return;
    }

    // 3. Invoke Android native notification bar if running on Android
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('showNotification', {
          'id': id ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'title': title,
          'body': body,
        });
      } catch (e) {
        debugPrint('[SYSTEM_NOTIFICATION_BAR ERROR] $e');
      }
    }
  }
}
