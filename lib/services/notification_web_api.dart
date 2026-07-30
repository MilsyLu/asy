// Web-only implementation — compiled exclusively when dart:js_interop is
// available (i.e. Flutter web builds). Never compiled by Android / iOS.

import 'dart:js_interop';

@JS('Notification')
extension type _WebNotification._(JSObject _) implements JSObject {
  external factory _WebNotification(String title, [JSObject? options]);
  external static String get permission;
  external set onclick(JSFunction? value);
}

/// Returns the browser's current Notification permission string
/// ("granted", "denied", or "default").
String get webNotificationPermission => _WebNotification.permission;

/// Displays a foreground push banner via the Web Notification API.
/// [opts] may contain 'body', 'icon', 'badge', 'tag', etc. [onClick], if
/// given, fires when the user clicks the banner (the tab is already open/
/// foreground at this point, since this API path only runs for
/// `FirebaseMessaging.onMessage` — no window focus/navigation needed,
/// unlike the background-push case handled by the service worker).
void showWebNotification(
  String title,
  Map<String, dynamic> opts, {
  void Function()? onClick,
}) {
  final jsOpts = opts.jsify()! as JSObject;
  final notification = _WebNotification(title, jsOpts);
  if (onClick != null) {
    notification.onclick = onClick.toJS;
  }
}

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, String title, String url);

@JS('window.location.pathname')
external String get _locationPathname;

/// Strips the `openTask` query param from the URL bar after it's been
/// handled (see `main_shell.dart`'s startup check) — without this,
/// refreshing the page would reopen the same task dialog forever, since
/// this app has no router to otherwise change the URL.
void clearOpenTaskQueryParam() {
  _replaceState(null, '', _locationPathname);
}
