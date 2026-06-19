import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../models/app_user.dart';

/// CRUD + streams for the `users` collection.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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

  /// Registers an FCM token for push notifications. Idempotent —
  /// `arrayUnion` is a no-op if the token is already stored, so the same
  /// device never produces duplicate entries. Empty tokens are rejected
  /// (Sprint 7.1 Part 8).
  Future<void> addFcmToken(String uid, String token) {
    if (token.isEmpty) return Future.value();
    return _collection.doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  Future<void> removeFcmToken(String uid, String token) {
    if (token.isEmpty) return Future.value();
    return _collection.doc(uid).update({
      'fcmTokens': FieldValue.arrayRemove([token]),
    });
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
}
