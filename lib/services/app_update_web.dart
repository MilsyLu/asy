// Web-only implementation — compiled exclusively when dart:js_interop is
// available (Flutter web builds). Never compiled on Android / iOS.

import 'dart:js_interop';

/// Reads the global flag set by the SW monitoring script in index.html.
/// True when Flutter's service worker has a new version in the `waiting` state.
@JS('__checu_sw_update_waiting')
external bool get _rawSwUpdateWaiting;

/// Calls the activation helper defined in index.html:
/// sends 'skipWaiting' to the waiting SW then reloads the page.
@JS('__checu_activate_update')
external void _rawActivate();

bool get webSwUpdateWaiting => _rawSwUpdateWaiting;

Future<void> activateWebUpdate() async => _rawActivate();
