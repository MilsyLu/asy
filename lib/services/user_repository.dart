import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/firestore_paths.dart';
import '../models/app_user.dart';

/// CRUD + streams for the `users` collection.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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
    return _collection.orderBy('name').snapshots().map(
        (snap) => snap.docs.map((d) => AppUser.fromDoc(d)).toList());
  }

  Stream<List<AppUser>> watchUsersByGroup(String groupId) {
    return _collection
        .where('groupId', isEqualTo: groupId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AppUser.fromDoc(d)).toList());
  }

  Future<List<AppUser>> getUsersByGroup(String groupId) async {
    final snap =
        await _collection.where('groupId', isEqualTo: groupId).get();
    return snap.docs.map((d) => AppUser.fromDoc(d)).toList();
  }

  Future<void> updateRole(String uid, String role) {
    return _collection.doc(uid).update({'role': role});
  }

  Future<void> updateGroup(String uid, String? groupId) {
    return _collection.doc(uid).update({'groupId': groupId});
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
  Future<void> addFcmToken(String uid, String token) async {
    if (token.isEmpty) return;

    final tokenShort = '${token.substring(0, 8)}...${token.substring(token.length - 8)}';
    debugPrint('[WEB_FCM_DIAG] addFcmToken() ENTRY uid=$uid token=$tokenShort');

    final staleHolders =
        await _collection.where('fcmTokens', arrayContains: token).get();
    debugPrint('[WEB_FCM_DIAG] addFcmToken(): stale query done — ${staleHolders.docs.length} doc(s) hold this token');
    for (final doc in staleHolders.docs) {
      if (doc.id == uid) continue;
      await doc.reference.update({
        'fcmTokens': FieldValue.arrayRemove([token]),
      });
      debugPrint('[FCM] Stale token removed from previous owner: ${doc.id}');
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
