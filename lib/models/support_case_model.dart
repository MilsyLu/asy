import 'package:cloud_firestore/cloud_firestore.dart';

/// A single uploaded screenshot/file attached to a support case.
class SupportCaseAttachment {
  const SupportCaseAttachment({
    required this.url,
    required this.name,
    required this.contentType,
    required this.size,
  });

  final String url;
  final String name;
  final String contentType;
  final int size;

  factory SupportCaseAttachment.fromMap(Map<String, dynamic> map) {
    return SupportCaseAttachment(
      url: map['url'] as String? ?? '',
      name: map['name'] as String? ?? '',
      contentType: map['contentType'] as String? ?? '',
      size: (map['size'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'url': url,
        'name': name,
        'contentType': contentType,
        'size': size,
      };
}

/// Represents a document in the `supportCases` collection — a client-reported
/// issue/ticket. `description` is the original report and is never
/// overwritten; every subsequent update (status/priority/assignee change,
/// comment) is instead appended to the `history` subcollection (see
/// [SupportCaseHistoryEntry]) so context is never lost.
class SupportCaseModel {
  const SupportCaseModel({
    required this.id,
    required this.caseNumber,
    required this.empresaId,
    required this.clientName,
    this.contactName = '',
    this.contactPhone = '',
    required this.subject,
    required this.description,
    required this.priority,
    required this.status,
    this.tags = const [],
    this.assignedUserId,
    this.attachments = const [],
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.reportedAt,
    required this.updatedAt,
    this.resolvedAt,
    this.reminderTime,
    this.reminderNote = '',
    this.reminderSetBy,
  });

  final String id;
  final int caseNumber;
  final String empresaId;
  final String clientName;
  final String contactName;
  final String contactPhone;
  final String subject;
  final String description;
  final String priority;
  final String status;
  final List<String> tags;
  final String? assignedUserId;
  final List<SupportCaseAttachment> attachments;
  final String createdBy;
  final String createdByName;

  /// When the record was typed into CheCu — automatic, never editable.
  final DateTime createdAt;

  /// When the client actually reported the issue — defaults to today at
  /// creation but is editable before saving, since a case is sometimes
  /// logged a day or two after it was actually reported. "Días sin
  /// resolver" is measured from here, not [createdAt], since that's the
  /// real urgency clock.
  final DateTime reportedAt;

  final DateTime updatedAt;
  final DateTime? resolvedAt;

  /// A one-off personal reminder for this case (e.g. "el lunes debo
  /// consultarle algo al equipo de tecno") — separate from the automatic
  /// 5/10/15-day "días sin resolver" reminders. Null means no reminder is
  /// scheduled. Only [reminderSetBy] gets notified when it fires (see
  /// `checkSupportCaseCustomReminders.js`), not the whole case's audience.
  final DateTime? reminderTime;
  final String reminderNote;
  final String? reminderSetBy;

  /// Whole days since [reportedAt] (when the client reported it — not when
  /// the record was typed in), frozen at [resolvedAt] once the case is
  /// resolved/closed.
  int daysOpen() {
    final end = resolvedAt ?? DateTime.now();
    return end.difference(reportedAt).inDays;
  }

  factory SupportCaseModel.fromMap(String id, Map<String, dynamic> map) {
    return SupportCaseModel(
      id: id,
      caseNumber: (map['caseNumber'] as num?)?.toInt() ?? 0,
      empresaId: map['empresaId'] as String? ?? '',
      clientName: map['clientName'] as String? ?? '',
      contactName: map['contactName'] as String? ?? '',
      contactPhone: map['contactPhone'] as String? ?? '',
      subject: map['subject'] as String? ?? '',
      description: map['description'] as String? ?? '',
      priority: map['priority'] as String? ?? '',
      status: map['status'] as String? ?? '',
      tags: (map['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      assignedUserId: map['assignedUserId'] as String?,
      attachments: (map['attachments'] as List<dynamic>?)
              ?.map((e) => SupportCaseAttachment.fromMap(e as Map<String, dynamic>))
              .toList() ??
          const [],
      createdBy: map['createdBy'] as String? ?? '',
      createdByName: map['createdByName'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reportedAt: (map['reportedAt'] as Timestamp?)?.toDate() ??
          (map['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      resolvedAt: (map['resolvedAt'] as Timestamp?)?.toDate(),
      reminderTime: (map['reminderTime'] as Timestamp?)?.toDate(),
      reminderNote: map['reminderNote'] as String? ?? '',
      reminderSetBy: map['reminderSetBy'] as String?,
    );
  }

  factory SupportCaseModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return SupportCaseModel.fromMap(doc.id, doc.data() ?? {});
  }
}
