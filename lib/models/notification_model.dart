import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `notifications` collection (Sprint 7.4 —
/// in-app notification center). Written server-side by Cloud Functions
/// alongside every FCM push, so it survives the user dismissing/missing the
/// system notification.
class NotificationModel {
  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final String? taskId;
  final bool isRead;
  final DateTime? createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.taskId,
    this.isRead = false,
    this.createdAt,
  });

  factory NotificationModel.fromMap(String id, Map<String, dynamic> map) {
    return NotificationModel(
      id: id,
      userId: map['userId'] as String? ?? '',
      type: map['type'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      taskId: map['taskId'] as String?,
      isRead: map['isRead'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory NotificationModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return NotificationModel.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap({bool withServerTimestamp = false}) {
    return {
      'userId': userId,
      'type': type,
      'title': title,
      'body': body,
      'taskId': taskId,
      'isRead': isRead,
      'createdAt': withServerTimestamp
          ? FieldValue.serverTimestamp()
          : (createdAt != null ? Timestamp.fromDate(createdAt!) : null),
    };
  }

  NotificationModel copyWith({
    String? type,
    String? title,
    String? body,
    String? taskId,
    bool? isRead,
  }) {
    return NotificationModel(
      id: id,
      userId: userId,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      taskId: taskId ?? this.taskId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}
