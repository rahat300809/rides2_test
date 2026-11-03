// File generated for DIU Ride Firebase integration
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCSOpUBZYClVhratJeK-OTRhypoRdTTjfk',
    appId: '1:848215124719:web:aa6543bbb965882fb0491a',
    messagingSenderId: '848215124719',
    projectId: 'diuride252',
    authDomain: 'diuride252.firebaseapp.com',
    storageBucket: 'diuride252.firebasestorage.app',
    measurementId: 'G-78EWC052SB',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCGQ_Dvm-3qD0pFMfBJ9ctIIm4OF6Tjvy8',
    appId: '1:848215124719:android:77908b3202850b73b0491a',
    messagingSenderId: '848215124719',
    projectId: 'diuride252',
    storageBucket: 'diuride252.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA_CampusDiuRideKey_DemoIos77',
    appId: '1:108392193821:ios:2390283019283019',
    messagingSenderId: '108392193821',
    projectId: 'diu-ride',
    storageBucket: 'diu-ride.appspot.com',
    iosBundleId: 'com.diu.ride.diuRide',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA_CampusDiuRideKey_DemoMac66',
    appId: '1:108392193821:ios:2390283019283019',
    messagingSenderId: '108392193821',
    projectId: 'diu-ride',
    storageBucket: 'diu-ride.appspot.com',
    iosBundleId: 'com.diu.ride.diuRide',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyA_CampusDiuRideKey_DemoWin55',
    appId: '1:108392193821:web:9102830192830192',
    messagingSenderId: '108392193821',
    projectId: 'diu-ride',
    authDomain: 'diu-ride.firebaseapp.com',
    storageBucket: 'diu-ride.appspot.com',
  );
}