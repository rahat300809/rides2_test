import 'url_launcher_helper_stub.dart'
    if (dart.library.html) 'url_launcher_helper_web.dart' as helper;

/// Universal safe URL launcher that opens links cleanly across Web and Mobile
Future<bool> launchSafeUrl(String urlString) => helper.launchSafeUrl(urlString);

/// Universal file/APK downloader that triggers native browser downloads on Web
Future<bool> launchDownloadFile(String urlString, {String? fileName}) =>
    helper.launchDownloadFile(urlString, fileName: fileName);

