import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable offline cache (works for mobile, desktop and web).
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  await initializeDateFormatting('es');
  await NotificationService.instance.initialize();

  runApp(const TaskFlowApp());
}
