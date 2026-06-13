import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// This top-level function MUST stay top-level (or static) — it is the
/// entry point Firebase Messaging invokes when a push notification
/// arrives while the app is terminated or in the background.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is auto-initialized by the plugin when the app is woken up
  // for a background message, so no extra setup is required here.
  // The system tray automatically displays the `notification` payload
  // for background/terminated messages, so nothing else to do.
  debugPrint('Background FCM message received: ${message.messageId}');
}

/// Wraps Firebase Cloud Messaging + flutter_local_notifications so the
/// app can show push notifications both in the foreground and
/// background, on Android and iOS.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'taskflow_high_importance',
    'TaskFlow Notificaciones',
    description: 'Notificaciones de tareas y recordatorios de TaskFlow',
    importance: Importance.high,
  );

  bool _initialized = false;

  /// Sets up local notification channels and FCM listeners. Call once
  /// during app startup, after `Firebase.initializeApp()`.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // --- Local notifications setup ---
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
    }

    // --- Permissions ---
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    // --- Foreground messages: show a local banner ---
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  /// Returns the current device FCM token, or null if unavailable
  /// (e.g. simulator without push capability, web without VAPID key).
  Future<String?> getToken() => _messaging.getToken();

  /// Notifies [onRefresh] whenever the FCM token rotates so it can be
  /// re-saved to the user's Firestore document.
  void onTokenRefresh(void Function(String token) onRefresh) {
    _messaging.onTokenRefresh.listen(onRefresh);
  }
}
