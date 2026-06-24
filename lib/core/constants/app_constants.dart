import 'package:flutter/material.dart';

/// User roles, stored in `users/{userId}.role`.
class AppRoles {
  AppRoles._();

  static const String superAdmin = 'super_admin';
  static const String trabajadorNormal = 'trabajador_normal';
}

/// Well-known status names used by reports & business logic.
/// The actual documents live in the `statuses` collection (admin-editable),
/// but these names are used to match status documents for special handling.
class AppStatusNames {
  AppStatusNames._();

  static const String pendiente = 'Pendiente';
  static const String completada = 'Completada';
  static const String reprogramada = 'Reprogramada';
  static const String cancelada = 'Cancelada';
}

/// Well-known task type names used by reports & business logic.
class AppTaskTypeNames {
  AppTaskTypeNames._();

  static const String instalacion = 'Instalación';
}

/// Notification types stored in `notifications/{id}.type` (Sprint 7.4).
/// Mirrors the `type` values the Cloud Functions layer already writes into
/// the FCM data payload (functions/src/onTaskCreate.js, checkReminders.js).
class AppNotificationTypes {
  AppNotificationTypes._();

  static const String taskCreatedAssigned = 'task_created_assigned';
  static const String taskCreatedGroup = 'task_created_group';
  static const String taskCreatedAdmin = 'task_created_admin';
  static const String taskReminder = 'task_reminder';
}

/// Values for `users/{userId}.pushNotificationMode` (Sprint 7.5.0 — replaces
/// the boolean `pushNotificationsEnabled` from Sprint 7.4.8). Only gates the
/// FCM push itself; the in-app `notifications` record (bell/historial/
/// contador) is always written server-side regardless of this preference
/// (see `functions/src/notifications.js` `sendNotificationToUser`).
///
/// `groupOnly` is only offered in the Settings UI for `super_admin` — the
/// field itself doesn't enforce that, so a worker doc could in principle
/// carry it (e.g. a direct Firestore edit), in which case it behaves exactly
/// as it does for an admin (only [AppNotificationTypes.taskCreatedGroup]).
class AppPushNotificationModes {
  AppPushNotificationModes._();

  static const String all = 'all';
  static const String assignedOnly = 'assigned_only';
  static const String groupOnly = 'group_only';
  static const String none = 'none';
}

class AppConstants {
  AppConstants._();

  static const String appName = 'CheCu';
  static const String appTagline = 'Chequeo y Cumplimiento de tareas';
  static const String appVersion = '1.0';
  static const String appDeveloper = 'CustoDesk 2026';

  /// Fixed institutional brand colors (Sprint 7.3.2A/B). Used by screens
  /// whose identity must not depend on the signed-in user's theme
  /// preference: Login and the app boot/splash hand-off in [TaskFlowApp].
  static const Color brandBackground = Color(0xFFF5F1E8);
  static const Color brandPrimary = Color(0xFF1A234A);
}
