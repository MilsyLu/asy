import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../models/notification_model.dart';

/// CRUD + queries for the `notifications` collection (Sprint 7.4 — in-app
/// notification center). Documents are written server-side by Cloud
/// Functions alongside every FCM push; this repository only reads and
/// flips `isRead`.
class NotificationRepository {
  NotificationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.notifications);

  /// All notifications for [userId], most recent first.
  Stream<List<NotificationModel>> watchNotifications(String userId) {
    return _collection
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => NotificationModel.fromDoc(d)).toList());
  }

  /// Live count of unread notifications for [userId], used by the bell badge.
  Stream<int> unreadCount(String userId) {
    return _collection
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> markAsRead(String id) {
    return _collection.doc(id).update({'isRead': true});
  }

  Future<void> markAllAsRead(String userId) async {
    final snap = await _collection
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Deletes a single notification (Sprint 7.4.7 Objetivo E) — swipe or
  /// the explicit delete button in [NotificationsPage].
  Future<void> deleteNotification(String id) {
    return _collection.doc(id).delete();
  }

  /// Deletes every notification belonging to [userId] (Sprint 7.4.7
  /// Objetivo F — "Vaciar historial"). Security rules independently
  /// enforce that a user can only ever delete their own notifications.
  Future<void> deleteAllNotifications(String userId) async {
    final snap = await _collection.where('userId', isEqualTo: userId).get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
