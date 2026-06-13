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
    apiKey: 'AIzaSyDqaVyEpEB7XN2g2YpLWhcNCzBKUc72f4s',
    appId: '1:74896792623:web:ee8b004fc6ce11cdf9bada',
    messagingSenderId: '74896792623',
    projectId: 'asyone-d8b68',
    authDomain: 'asyone-d8b68.firebaseapp.com',
    storageBucket: 'asyone-d8b68.firebasestorage.app',
    measurementId: 'G-58PJEM68CW',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA7kt3XTS-A66THH-cMPOzCg9oL3Y29_Qs',
    appId: '1:74896792623:android:35ee092d1a860adef9bada',
    messagingSenderId: '74896792623',
    projectId: 'asyone-d8b68',
    storageBucket: 'asyone-d8b68.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB-fucvHZmkotjBI5hbpP88s9_vJMEOvyc',
    appId: '1:74896792623:ios:fae162dcc816e3aef9bada',
    messagingSenderId: '74896792623',
    projectId: 'asyone-d8b68',
    storageBucket: 'asyone-d8b68.firebasestorage.app',
    iosBundleId: 'com.taskflow.taskflowExecutive',
  );
}
