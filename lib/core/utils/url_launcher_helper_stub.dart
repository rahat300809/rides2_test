// Universal URL Launcher for Native platforms (Android, iOS, macOS, Windows, Linux)
import 'package:url_launcher/url_launcher.dart';

Future<bool> launchSafeUrl(String urlString) async {
  try {
    final uri = Uri.parse(urlString);
    return await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    return false;
  }
}

Future<bool> launchDownloadFile(String urlString, {String? fileName}) async {
  try {
    final uri = Uri.parse(urlString);
    return await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    return false;
  }
}

