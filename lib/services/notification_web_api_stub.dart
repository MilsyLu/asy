// Stub — compiled on Android / iOS / desktop where dart:js_interop is
// unavailable. Every call-site in NotificationService is already inside an
// `if (kIsWeb)` guard, so none of these bodies are ever reached at runtime.

String get webNotificationPermission => 'denied';

void showWebNotification(String title, Map<String, dynamic> opts) {}
