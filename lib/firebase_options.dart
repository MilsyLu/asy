// File generated normally by the FlutterFire CLI.
//
// IMPORTANT: This file contains PLACEHOLDER values so the project
// compiles out of the box. Before running the app against a real
// Firebase project, replace this file by running:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// That command will overwrite this file with the real values for your
// Firebase project (Android, iOS and Web). See README.md for the full
// setup walkthrough.
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
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'run `flutterfire configure` to add support.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'run `flutterfire configure` to add support.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'run `flutterfire configure` to add support.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB3vZ7n8gFrh_H6pRcUwoRsul1X-mWl35g',
    appId: '1:1065136957290:web:6014aa111c59097b69a713',
    messagingSenderId: '1065136957290',
    projectId: 'chhecu',
    authDomain: 'chhecu.firebaseapp.com',
    storageBucket: 'chhecu.firebasestorage.app',
    measurementId: 'G-VMP8G2YRY9',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCgaYgUF4_qM2Pn23nm-GhSv3K3a-blcag',
    appId: '1:1065136957290:android:6f309f961fe31dd369a713',
    messagingSenderId: '1065136957290',
    projectId: 'chhecu',
    storageBucket: 'chhecu.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD3mDEgZIfD-yleWrRiLh7BFww1EfB9fU8',
    appId: '1:1065136957290:ios:d990275193c2cd1969a713',
    messagingSenderId: '1065136957290',
    projectId: 'chhecu',
    storageBucket: 'chhecu.firebasestorage.app',
    iosBundleId: 'com.taskflow.taskflowExecutive',
  );
}
