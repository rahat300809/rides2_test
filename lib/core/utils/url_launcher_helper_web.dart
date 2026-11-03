// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<bool> launchSafeUrl(String urlString) async {
  try {
    html.window.open(urlString, '_blank');
    return true;
  } catch (e) {
    return false;
  }
}

Future<bool> launchDownloadFile(String urlString, {String? fileName}) async {
  try {
    final anchor = html.AnchorElement(href: urlString)
      ..setAttribute('download', fileName ?? 'diu_ride.apk')
      ..target = '_blank'
      ..rel = 'noopener noreferrer';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (e) {
    try {
      html.window.open(urlString, '_blank');
      return true;
    } catch (_) {
      return false;
    }
  }
}

