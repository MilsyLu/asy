import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/firestore_paths.dart';
import '../models/app_user.dart';

/// CRUD + streams for the `users` collection.
///
/// Multi-tenant: [empresaId] is optional here (unlike the other
/// repositories) because this repository is used two ways — (a) the
/// tenant-scoped instance held by CatalogProvider, which needs it to filter
/// [watchAllUsers], and (b) the
/// root-level instance AuthProvider uses to bootstrap the signed-in user's
/// own profile via [watchUser] *before* their empresaId is even known (a
/// self-read of `users/{uid}` is always allowed by firestore.rules
/// regardless of empresaId, since it compares the doc to itself). Every
/// other method here operates on a specific `uid` directly and doesn't need
/// empresaId either — only the three list/query methods do.
class UserRepository {
  UserRepository({this.empresaId, FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String? empresaId;

  /// Max FCM tokens kept per user (Sprint 7.4.2 — Parte 1.4). Beyond this,
  /// the oldest token is evicted so multi-device logins never grow the
  /// array unbounded (reinstalls/`flutter run`/device changes otherwise
  /// leave stale tokens behind forever, since they're only pruned on
  /// explicit sign-out or reactively when FCM reports them invalid).
  static const int _maxFcmTokens = 3;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.users);

  Stream<AppUser?> watchUser(String uid) {
    return _collection.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromDoc(doc);
    });
  }

  Future<AppUser?> getUser(String uid) async {
    final doc = await _collection.doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromDoc(doc);
  }

  Stream<List<AppUser>> watchAllUsers() {
    assert(empresaId != null, 'watchAllUsers() requires a tenant-scoped UserRepository');
    return _collection
        .where('empresaId', isEqualTo: empresaId)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) => AppUser.fromDoc(d)).toList());
  }

  Future<void> updateRole(String uid, String role) {
    return _collection.doc(uid).update({'role': role});
  }

  /// Replaces the full set of teams [uid] belongs to — used by the "Equipos"
  /// multi-select on the Usuarios screen, which edits an arbitrary new set
  /// at once rather than adding/removing one at a time.
  Future<void> setGroupIds(String uid, List<String> groupIds) {
    return _collection.doc(uid).update({'groupIds': groupIds});
  }

  /// Adds [uid] to [groupId] without disturbing their other teams — used by
  /// the Equipos screen's per-team membership checklist.
  Future<void> addToGroup(String uid, String groupId) {
    return _collection.doc(uid).update({
      'groupIds': FieldValue.arrayUnion([groupId]),
    });
  }

  /// Removes [uid] from [groupId] without disturbing their other teams.
  Future<void> removeFromGroup(String uid, String groupId) {
    return _collection.doc(uid).update({
      'groupIds': FieldValue.arrayRemove([groupId]),
    });
  }

  /// Sets the teams an `admin_equipo` user manages. Only meaningful for that
  /// role — see [AppUser.managedGroupIds].
  Future<void> updateManagedGroupIds(String uid, List<String> groupIds) {
    return _collection.doc(uid).update({'managedGroupIds': groupIds});
  }

  /// Sets the granular permission flags for an `admin_equipo` user — see
  /// [AppPermissions]/[AppUser.permissions]. Uses `merge: true` so legacy
  /// documents without the field are upgraded in place.
  Future<void> updatePermissions(String uid, Map<String, bool> permissions) {
    return _collection
        .doc(uid)
        .set({'permissions': permissions}, SetOptions(merge: true));
  }

  Future<void> updateName(String uid, String name) {
    return _collection.doc(uid).update({'name': name});
  }

  /// Persists the user's visual preferences (FASE 3). Uses `merge: true`
  /// so legacy documents without these fields are upgraded in place.
  Future<void> updateThemePreferences(
    String uid, {
    String? themeMode,
    String? accentColor,
  }) {
    final data = <String, dynamic>{
      'themeMode': ?themeMode,
      'accentColor': ?accentColor,
    };
    if (data.isEmpty) return Future.value();
    return _collection.doc(uid).set(data, SetOptions(merge: true));
  }

  /// Saves or removes the user's profile photo URL.
  /// Passing null deletes the field so [AppUser.photoUrl] falls back to null.
  Future<void> updatePhotoUrl(String uid, String? photoUrl) {
    if (photoUrl == null) {
      return _collection.doc(uid).update({'photoUrl': FieldValue.delete()});
    }
    return _collection.doc(uid).set({'photoUrl': photoUrl}, SetOptions(merge: true));
  }

  /// Registers an FCM token for push notifications. Idempotent — a token
  /// already present is left untouched (no rewrite, no log). New tokens
  /// are appended; if that pushes the array past [_maxFcmTokens], the
  /// oldest token is evicted so multi-device logins never grow the array
  /// unbounded (Sprint 7.4.2 — Parte 1.4). Empty tokens are rejected
  /// (Sprint 7.1 Part 8). Runs in a transaction since two devices can
  /// register concurrently.
  ///
  /// Sprint 7.4.6 Bug 1: an FCM token identifies a *device install*, not an
  /// account — if a previous user on this device didn't cleanly sign out
  /// (force-close, crash, hot-restart during dev), their `fcmTokens` array
  /// can still contain this device's token. FCM delivers by token, so that
  /// stale registration keeps receiving pushes addressed to the old user
  /// (and gets correctly recorded under *their* `userId` in `notifications`)
  /// even after a different user is now signed in here — the new user's
  /// device displays the push, but its own bell/historial query never
  /// matches a doc that was correctly written for someone else. Stripping
  /// the token from every other account before attaching it here keeps a
  /// token bound to exactly one account at a time.
  ///
  /// [callerEmpresaId] scopes the stale-holder scan to the caller's own
  /// tenant — required since firestore.rules now requires every `users`
  /// list query to filter by empresaId (a query without it is rejected
  /// outright, not silently unfiltered). When null (only possible for a
  /// not-yet-migrated legacy account) the stale-holder scan is skipped
  /// entirely rather than attempting a query the rules would reject — a
  /// stale token from a different tenant on a shared device is still
  /// eventually pruned when FCM reports it invalid (see
  /// `functions/src/notifications.js`), so this is a minor push-delivery
  /// efficiency trade-off, not a confidentiality one.
  Future<void> addFcmToken(String uid, String token, {String? callerEmpresaId}) async {
    if (token.isEmpty) return;

    final tokenShort = '${token.substring(0, 8)}...${token.substring(token.length - 8)}';
    debugPrint('[WEB_FCM_DIAG] addFcmToken() ENTRY uid=$uid token=$tokenShort');

    if (callerEmpresaId != null) {
      final staleHolders = await _collection
          .where('empresaId', isEqualTo: callerEmpresaId)
          .where('fcmTokens', arrayContains: token)
          .get();
      debugPrint('[WEB_FCM_DIAG] addFcmToken(): stale query done — ${staleHolders.docs.length} doc(s) hold this token');
      for (final doc in staleHolders.docs) {
        if (doc.id == uid) continue;
        await doc.reference.update({
          'fcmTokens': FieldValue.arrayRemove([token]),
        });
        debugPrint('[FCM] Stale token removed from previous owner: ${doc.id}');
      }
    }

    final docRef = _collection.doc(uid);
    debugPrint('[WEB_FCM_DIAG] addFcmToken(): starting Firestore transaction...');
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      final current = (snap.data()?['fcmTokens'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          <String>[];
      debugPrint('[WEB_FCM_DIAG] addFcmToken(): inside transaction — current.length=${current.length} alreadyContains=${current.contains(token)}');
      if (current.contains(token)) {
        debugPrint('[WEB_FCM_DIAG] addFcmToken(): token already present — no write needed');
        return;
      }

      current.add(token);
      String? evicted;
      if (current.length > _maxFcmTokens) {
        evicted = current.removeAt(0);
      }

      transaction.set(docRef, {'fcmTokens': current}, SetOptions(merge: true));
      debugPrint('[WEB_FCM_DIAG] addFcmToken(): transaction.set() queued — new count=${current.length}');
      debugPrint('[FCM] Token added: $uid (${current.length}/$_maxFcmTokens)');
      if (evicted != null) {
        debugPrint('[FCM] Token limit reached: $uid, oldest token evicted');
      }
    });
    debugPrint('[WEB_FCM_DIAG] addFcmToken(): Firestore transaction COMPLETED OK');
  }

  Future<void> removeFcmToken(String uid, String token) async {
    if (token.isEmpty) return;
    await _collection.doc(uid).update({
      'fcmTokens': FieldValue.arrayRemove([token]),
    });
    debugPrint('[FCM] Token removed: $uid');
  }

  Future<void> deleteUserDoc(String uid) {
    return _collection.doc(uid).delete();
  }

  /// Toggles whether [uid] may sign in and receive new task assignments/
  /// notifications (Sprint 7.3.1). Uses `merge: true` so legacy documents
  /// without the field are upgraded in place.
  Future<void> setActive(String uid, bool isActive) {
    return _collection
        .doc(uid)
        .set({'isActive': isActive}, SetOptions(merge: true));
  }

  /// Sets which FCM push categories [uid] wants to receive (Sprint 7.5.0 —
  /// replaces the boolean `pushNotificationsEnabled` of Sprint 7.4.8, now
  /// obsolete and no longer written, though still read as a fallback — see
  /// `AppUser._resolvePushNotificationMode`). [mode] is one of
  /// [AppPushNotificationModes]. The in-app `notifications` record is
  /// always written server-side regardless of this preference. Uses
  /// `merge: true` so legacy documents without the field are upgraded in
  /// place.
  Future<void> updatePushNotificationMode(String uid, String mode) {
    return _collection
        .doc(uid)
        .set({'pushNotificationMode': mode}, SetOptions(merge: true));
  }
}
