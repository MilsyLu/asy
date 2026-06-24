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
  debugPrint(
    '[FCM_TIMING]\npush_received\ntaskId=${message.data['taskId'] ?? "n/a"}\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
  );
  debugPrint('Background FCM message received: ${message.messageId}');
}

/// Parsed `{type, taskId}` data payload carried by business push
/// notifications (Sprint 7.1 Part 7 — `task_created` / `task_completed` /
/// `task_reprogrammed`, etc., added in later sprints). Only the shape is
/// established here; nothing currently dispatches on [type] — that's for
/// whichever sprint adds in-app navigation on notification tap.
class NotificationPayload {
  const NotificationPayload({this.type, this.taskId});

  final String? type;
  final String? taskId;

  factory NotificationPayload.fromMessage(RemoteMessage message) {
    return NotificationPayload(
      type: message.data['type'] as String?,
      taskId: message.data['taskId'] as String?,
    );
  }

  @override
  String toString() => 'NotificationPayload(type: $type, taskId: $taskId)';
}

/// Wraps Firebase Cloud Messaging + flutter_local_notifications.
///
/// Handles FCM push notifications: foreground display via
/// [_showForegroundNotification], background/terminated via
/// [firebaseMessagingBackgroundHandler], tap via [handleOpenedNotification].
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

  /// Sprint 7.4.3 Parte 1 — the *only* place `onTokenRefresh.listen(...)` is
  /// ever called (inside [initialize], once, guarded by [_initialized]).
  /// Callers that need to react to a token rotation (currently just
  /// [AuthProvider], to re-save the token under the signed-in user) swap
  /// this handler reference via [setTokenRefreshHandler] instead of
  /// creating their own subscription — re-running login logic (e.g. on
  /// every `users/{uid}` snapshot) only replaces the callback, it never
  /// grows the number of underlying stream listeners.
  void Function(String token)? _tokenRefreshHandler;

  /// Sets up local notification channels and FCM listeners.
  /// Call once during app startup, after `Firebase.initializeApp()`.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // --- Local notifications setup ---
    // Sprint 7.3.3: must be a monochrome white-on-transparent drawable, not
    // the full-color launcher mipmap — Android renders status-bar icons from
    // the alpha channel only, so a color icon shows up as a solid block.
    const androidInit = AndroidInitializationSettings('@drawable/ic_notification');
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

    // --- FCM permissions (covers local notifications on iOS too) ---
    // Sprint 7.4.5 Objetivo 1: this used to be requested right here,
    // blocking `runApp()` on the OS permission prompt (which can wait
    // indefinitely on user interaction, especially on iOS). It's now
    // requested by the caller (see `main.dart`) only after the first frame
    // is on screen — every other step of `initialize()` is unchanged and
    // still completes before `runApp()`.

    // --- Foreground messages: show a local banner ---
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // --- Token rotation: single subscription for the app's lifetime
    // (Sprint 7.4.3 Parte 1) — forwards to whatever handler is currently
    // registered via [setTokenRefreshHandler] instead of letting callers
    // create their own `.listen()` each time they need to react to it.
    _messaging.onTokenRefresh.listen((token) => _tokenRefreshHandler?.call(token));

    // --- Background/terminated delivery: official Firebase entry point ---
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // --- Opened-notification handling (Sprint 7.1 Parts 6-7) ---
    // App was backgrounded and the user tapped the push to bring it forward.
    FirebaseMessaging.onMessageOpenedApp.listen(handleOpenedNotification);

    // App was terminated and got launched by tapping the push; FCM buffers
    // that one message for retrieval right after startup.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      handleOpenedNotification(initialMessage);
    }
  }

  /// Requests notification permission from the OS — required on iOS and
  /// Android 13+ (silently granted on older Android). Split out from
  /// [initialize] as its own responsibility per the FCM service breakdown
  /// (Sprint 7.1 Part 3).
  Future<void> requestPermissions() async {
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
  }

  /// Called when the user taps a push notification that brought the app to
  /// the foreground from background or terminated state (Sprint 7.1 Parts
  /// 6-7). For now this only logs the parsed payload — no in-app navigation
  /// happens yet; that's left for the sprint that adds business
  /// notifications (task created/completed/reprogrammed) to dispatch on.
  void handleOpenedNotification(RemoteMessage message) {
    final payload = NotificationPayload.fromMessage(message);
    debugPrint(
      '[FCM_TIMING] Push opened taskId=${payload.taskId ?? "n/a"} ts=${DateTime.now().millisecondsSinceEpoch}',
    );
    debugPrint('Notification opened: $payload');
  }

  void _showForegroundNotification(RemoteMessage message) {
    debugPrint(
      '[FCM_TIMING]\npush_received\ntaskId=${message.data['taskId'] ?? "n/a"}\ntimestamp=${DateTime.now().millisecondsSinceEpoch}',
    );
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
          icon: '@drawable/ic_notification',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the current device FCM token, or null if unavailable
  /// (e.g. simulator without push capability, web without VAPID key).
  Future<String?> getToken() => _messaging.getToken();

  /// Sets (or clears, with `null`) the callback invoked whenever the FCM
  /// token rotates, so it can be re-saved to the user's Firestore document.
  /// Replaces any previously-registered handler — it does NOT add another
  /// `onTokenRefresh` subscription (Sprint 7.4.3 Parte 1; see
  /// [_tokenRefreshHandler]). Callers should pass `null` on sign-out so a
  /// late token rotation doesn't write to a stale, now-logged-out uid.
  void setTokenRefreshHandler(void Function(String token)? handler) {
    _tokenRefreshHandler = handler;
  }
}
