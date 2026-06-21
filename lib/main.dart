import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  debugPrint(
    '[PERF]\napp_start\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
  );

  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable offline cache (works for mobile, desktop and web).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  await initializeDateFormatting('es');
  await NotificationService.instance.initialize();

  runApp(const TaskFlowApp());

  // Sprint 7.4.5 Objetivo 1: the OS notification-permission prompt is
  // requested only after the first frame renders, so it never delays
  // `runApp()`/the initial UI — fired here without an `await` precisely so
  // `startup_complete` below doesn't wait on the user dismissing it.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint(
      '[PERF]\nfirst_frame\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
    );
    unawaited(NotificationService.instance.requestPermissions());
    debugPrint(
      '[PERF]\nstartup_complete\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
    );
  });
}
