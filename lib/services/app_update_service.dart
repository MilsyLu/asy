import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/firestore_paths.dart';
import 'app_update_stub.dart'
    if (dart.library.js_interop) 'app_update_web.dart';

/// Detects when a new version of CheCu is available and notifies listeners.
///
/// Detection has two layers:
///   1. Firestore: watches `systemConfig/settings.appVersion`. When the remote
///      version is semantically newer than [AppConstants.appVersion] (the local
///      build), [showBanner] becomes true.
///   2. Service Worker (web only): the JS snippet in index.html monitors
///      Flutter's SW for an `installed`-but-waiting state and exposes
///      `window.__checu_sw_update_waiting`. [_swTimer] polls this flag every
///      5 minutes as a fallback for cases where Firestore is not updated.
///
/// The admin workflow is:
///   1. Bump [AppConstants.appVersion] in the Dart source (e.g., '1.0' → '1.1').
///   2. Build & deploy: `firebase deploy --only hosting`.
///   3. Update `systemConfig/settings.appVersion` to the same string in
///      Firestore (Firebase Console or Admin SDK).
///
/// Clients running the old version receive the Firestore change immediately
/// via the stream and see the banner. They click "Actualizar ahora", which
/// activates the waiting SW and reloads — now serving the new version.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService() {
    _startFirestoreWatch();
    if (kIsWeb) {
      _swTimer = Timer.periodic(const Duration(minutes: 5), (_) => _checkSw());
    }
  }

  bool _updateAvailable = false;
  bool _dismissed = false;
  String? _remoteVersion;

  /// Whether the update banner should be visible.
  bool get showBanner => _updateAvailable && !_dismissed;

  /// The remote version string from Firestore, if available. Used to display
  /// "Nueva versión disponible (v1.1)" in the banner.
  String? get remoteVersion => _remoteVersion;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _fsSub;
  Timer? _swTimer;

  void _startFirestoreWatch() {
    _fsSub = FirebaseFirestore.instance
        .collection(FirestoreCollections.systemConfig)
        .doc(FirestoreCollections.systemConfigSettings)
        .snapshots()
        .listen(_onSnapshot, onError: (_) {});
  }

  void _onSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data();
    if (data == null) return;
    final remote = data['appVersion'] as String?;
    if (remote != null && _isRemoteNewer(remote, AppConstants.appVersion)) {
      _markUpdate(remote);
    } else {
      _checkSw();
    }
  }

  void _checkSw() {
    if (!kIsWeb) return;
    if (webSwUpdateWaiting && !_updateAvailable) {
      _markUpdate(null);
    }
  }

  void _markUpdate(String? version) {
    if (_updateAvailable && _remoteVersion == version) return;
    _updateAvailable = true;
    _dismissed = false;
    _remoteVersion = version;
    notifyListeners();
  }

  /// Hides the banner until the next version bump or SW update is detected.
  void dismiss() {
    _dismissed = true;
    notifyListeners();
  }

  /// Web: sends 'skipWaiting' to the waiting SW and reloads the page.
  /// Mobile/desktop: no-op (updates come through the app stores).
  Future<void> activateUpdate() async {
    if (kIsWeb) await activateWebUpdate();
  }

  /// Returns true when [remote] is semantically newer than [local].
  /// Compares each dot-separated numeric segment left-to-right.
  static bool _isRemoteNewer(String remote, String local) {
    List<int> parse(String v) =>
        v.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final r = parse(remote);
    final l = parse(local);
    final len = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < len; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }

  @override
  void dispose() {
    _fsSub?.cancel();
    _swTimer?.cancel();
    super.dispose();
  }
}
