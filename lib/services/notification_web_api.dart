// Web-only implementation — compiled exclusively when dart:js_interop is
// available (i.e. Flutter web builds). Never compiled by Android / iOS.

import 'dart:js_interop';

@JS('Notification')
extension type _WebNotification._(JSObject _) implements JSObject {
  external factory _WebNotification(String title, [JSObject? options]);
  external static String get permission;
  external set onclick(JSFunction? value);
  external void close();
}

@JS('window.focus')
external void _focusWindow();

/// Returns the browser's current Notification permission string
/// ("granted", "denied", or "default").
String get webNotificationPermission => _WebNotification.permission;

/// Displays a foreground push banner via the Web Notification API.
/// [opts] may contain 'body', 'icon', 'badge', 'tag', etc. [onClick], if
/// given, fires when the user clicks the banner.
///
/// "Foreground" here means the tab is *running*, not that the user is looking
/// at it: `FirebaseMessaging.onMessage` fires for a visible tab and for a
/// merely-backgrounded one alike. So the click handler must bring the window
/// forward itself — unlike a service-worker notification, clicking a
/// page-created one does not focus anything on its own. Without the
/// `window.focus()` below the callback still runs and the task dialog still
/// opens, but it opens behind whatever the user is actually looking at, which
/// is indistinguishable from the click doing nothing at all.
void showWebNotification(
  String title,
  Map<String, dynamic> opts, {
  void Function()? onClick,
}) {
  final jsOpts = opts.jsify()! as JSObject;
  final notification = _WebNotification(title, jsOpts);
  notification.onclick = () {
    try {
      _focusWindow();
    } catch (_) {
      // Focus can be refused by the browser; still run the callback so the
      // target at least opens in the tab.
    }
    onClick?.call();
    notification.close();
  }.toJS;
}

@JS('window.__checuOnNotificationClick')
external set _onNotificationClick(JSFunction? value);

@JS('window.__checuNotificationClick')
external JSAny? _pendingNotificationClick;

/// Receives background-push notification clicks from `web/index.html`.
///
/// The Firebase SW SDK focuses the existing tab and posts the payload to it
/// instead of navigating; `firebase_messaging_web` does not surface that as
/// `onMessageOpenedApp`, so index.html catches the raw message and calls the
/// hook installed here. Anything that arrived before this ran is buffered on
/// the window and drained immediately, which covers a click landing while the
/// app is still booting.
void setNotificationClickHandler(void Function(String url) handler) {
  _onNotificationClick = ((JSString url) => handler(url.toDart)).toJS;

  final pending = _pendingNotificationClick;
  if (pending != null) {
    _pendingNotificationClick = null;
    handler((pending as JSString).toDart);
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
