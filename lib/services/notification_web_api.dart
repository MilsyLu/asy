// Web-only implementation — compiled exclusively when dart:js_interop is
// available (i.e. Flutter web builds). Never compiled by Android / iOS.

import 'dart:js_interop';

@JS('Notification')
extension type _WebNotification._(JSObject _) implements JSObject {
  external factory _WebNotification(String title, [JSObject? options]);
  external static String get permission;
}

/// Returns the browser's current Notification permission string
/// ("granted", "denied", or "default").
String get webNotificationPermission => _WebNotification.permission;

/// Displays a foreground push banner via the Web Notification API.
/// [opts] may contain 'body', 'icon', 'badge', 'tag', etc.
void showWebNotification(String title, Map<String, dynamic> opts) {
  final jsOpts = opts.jsify()! as JSObject;
  _WebNotification(title, jsOpts);
}
