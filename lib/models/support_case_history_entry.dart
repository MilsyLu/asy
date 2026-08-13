import 'package:cloud_firestore/cloud_firestore.dart';

/// Entry types stored in `supportCases/{id}/history`.
class SupportCaseHistoryType {
  SupportCaseHistoryType._();

  static const String created = 'created';
  static const String comment = 'comment';
  static const String statusChanged = 'status_changed';
  static const String priorityChanged = 'priority_changed';
  static const String assigneeChanged = 'assignee_changed';
  static const String attachmentAdded = 'attachment_added';
  static const String tagsChanged = 'tags_changed';
  static const String reminderChanged = 'reminder_changed';
}

/// A single entry in a support case's timeline — this is what "Seguimiento"
/// shows instead of ever overwriting the case's original description.
class SupportCaseHistoryEntry {
  const SupportCaseHistoryEntry({
    required this.id,
    required this.type,
    required this.text,
    required this.authorId,
    required this.authorName,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String text;
  final String authorId;
  final String authorName;
  final DateTime createdAt;

  factory SupportCaseHistoryEntry.fromMap(String id, Map<String, dynamic> map) {
    return SupportCaseHistoryEntry(
      id: id,
      type: map['type'] as String? ?? '',
      text: map['text'] as String? ?? '',
      authorId: map['authorId'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  factory SupportCaseHistoryEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return SupportCaseHistoryEntry.fromMap(doc.id, doc.data() ?? {});
  }
}
