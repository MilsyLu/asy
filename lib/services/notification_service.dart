import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

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
/// Handles both:
/// - FCM push notifications (foreground display via [_showForegroundNotification],
///   background/terminated via [firebaseMessagingBackgroundHandler], tap via
///   [handleOpenedNotification])
/// - Scheduled local reminders ([scheduleReminder] / [cancelReminder])
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

  /// Sets up local notification channels, timezone data, and FCM listeners.
  /// Call once during app startup, after `Firebase.initializeApp()`.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Timezone database for scheduled local notifications.
    // Uses the absolute epoch of each DateTime, so no device-TZ lookup needed.
    tz_data.initializeTimeZones();

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
    await requestPermissions();

    // --- Foreground messages: show a local banner ---
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

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
    debugPrint('Notification opened: $payload');
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
  // Scheduled local reminders
  // ---------------------------------------------------------------------------

  /// Schedules a local notification that fires at [reminderTime].
  ///
  /// - No-op if [reminderTime] is already in the past.
  /// - Safe to call more than once for the same [taskId]: the notification
  ///   ID is deterministic, so a new call overwrites the previous one.
  /// - Errors are caught and logged; callers do not need to handle them.
  Future<void> scheduleReminder({
    required String taskId,
    required String clientName,
    required String taskTypeName,
    required String taskHour,
    required DateTime reminderTime,
  }) async {
    if (reminderTime.isBefore(DateTime.now())) return;

    try {
      final scheduledDate = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC,
        reminderTime.millisecondsSinceEpoch,
      );

      await _localNotifications.zonedSchedule(
        _idForTask(taskId),
        '⏰ Recordatorio',
        '$clientName\n$taskTypeName · $taskHour',
        scheduledDate,
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
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('scheduleReminder failed for $taskId: $e');
    }
  }

  /// Cancels the pending scheduled notification for [taskId], if any.
  Future<void> cancelReminder(String taskId) async {
    try {
      await _localNotifications.cancel(_idForTask(taskId));
    } catch (e) {
      debugPrint('cancelReminder failed for $taskId: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Deterministic, stable notification ID derived from [taskId].
  ///
  /// Dart VM does not randomize `String.hashCode` (unlike Java/Python), so
  /// this value is stable across app restarts — essential for cancellation.
  /// The modulo keeps it within the 32-bit signed int range required by
  /// flutter_local_notifications on Android.
  static int _idForTask(String taskId) => taskId.hashCode.abs() % 2000000000;

  /// Returns the current device FCM token, or null if unavailable
  /// (e.g. simulator without push capability, web without VAPID key).
  Future<String?> getToken() => _messaging.getToken();

  /// Notifies [onRefresh] whenever the FCM token rotates so it can be
  /// re-saved to the user's Firestore document.
  void onTokenRefresh(void Function(String token) onRefresh) {
    _messaging.onTokenRefresh.listen(onRefresh);
  }
}
