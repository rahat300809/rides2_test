import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/core/theme/app_theme.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/core/services/system_notification_service.dart';
import 'package:diu_ride/features/auth/presentation/screens/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize native Google Maps Android renderer
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
      if (mapsImplementation is GoogleMapsFlutterAndroid) {
        mapsImplementation.useAndroidViewSurface = true;
        await mapsImplementation.initializeWithRenderer(AndroidMapRenderer.latest);
      }
    } catch (e) {
      debugPrint('GoogleMaps Android renderer init note: $e');
    }
  }

  // Initialize System Notification service & permissions (Mobile Notification Bar & Web Browser Tray)
  try {
    await SystemNotificationService.initialize();
  } catch (e) {
    debugPrint('SystemNotificationService init: $e');
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init fallback: $e');
  }

  try {
    // Initialize App Configuration pointing to self-hosted API & WebSockets
    AppConfig.initialize(
      environment: Environment.production,
      useMockData: false,
    );
  } catch (e) {
    debugPrint('AppConfig init error: $e');
  }

  PreferencesService? preferencesService;
  try {
    // Initialize SharedPreferences (keeps login persistent until manual logout)
    preferencesService = await PreferencesService.init();
    await preferencesService.seedDefaultAccounts();
  } catch (e) {
    debugPrint('PreferencesService init error: $e');
  }

  try {
    // Set transparent system navigation & status bars
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  } catch (_) {}

  runApp(
    ProviderScope(
      overrides: [
        if (preferencesService != null)
          preferencesProvider.overrideWithValue(preferencesService),
      ],
      child: const DiuRideApp(),
    ),
  );
}

class SmoothScrollBehavior extends MaterialScrollBehavior {
  const SmoothScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (kIsWeb) {
      // ClampingScrollPhysics eliminates rubber-band drag lag on mobile/desktop web browsers
      return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
    }
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class DiuRideApp extends StatelessWidget {
  const DiuRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DIU Ride',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const SmoothScrollBehavior(),
      home: const SplashScreen(),
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const SplashScreen(),
      ),
    );
  }
}
