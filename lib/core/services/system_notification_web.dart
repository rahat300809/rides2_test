// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Native Web browser Notification Bar / Banner implementation using HTML5 Notification API
void triggerWebNotification(String title, String body, String? id) {
  try {
    if (!html.Notification.supported) {
      return;
    }

    if (html.Notification.permission == 'granted') {
      final n = html.Notification(
        title,
        body: body,
        icon: 'icons/Icon-192.png',
        tag: id ?? 'diu_ride_alert_${DateTime.now().millisecondsSinceEpoch}',
      );
      n.onClick.listen((_) {
        try {
          n.close();
        } catch (_) {}
      });
    } else if (html.Notification.permission != 'denied') {
      html.Notification.requestPermission().then((permission) {
        if (permission == 'granted') {
          final n = html.Notification(
            title,
            body: body,
            icon: 'icons/Icon-192.png',
            tag: id ?? 'diu_ride_alert_${DateTime.now().millisecondsSinceEpoch}',
          );
          n.onClick.listen((_) {
            try {
              n.close();
            } catch (_) {}
          });
        }
      });
    }
  } catch (e) {
    // Graceful fallback if browser notification policy restricts non-HTTPS or non-user gestures
    // ignore: avoid_print
    print('[WEB_NOTIFICATION ERROR] $e');
  }
}

/// Prompt user for browser desktop/mobile notification permission
void requestWebNotificationPermission() {
  try {
    if (html.Notification.supported && html.Notification.permission == 'default') {
      html.Notification.requestPermission();
    }
  } catch (_) {}
}
