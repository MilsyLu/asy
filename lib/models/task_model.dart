import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/date_utils.dart';

/// Represents a document in the `tasks` collection.
class TaskModel {
  final String id;
  final String hour; // "HH:MM"
  final String assignedUserId;
  final String? taskTypeId;
  final String clientName;
  final String clientPhone;
  /// Links this task to a `clients/{id}` record. Nullable: legacy tasks
  /// (created before the Clientes feature) never have one, and even new
  /// tasks may briefly not until save-time auto-linking resolves it. See
  /// [ClientModel] and the `_resolveOrCreateClientId` helper duplicated in
  /// `add_edit_task_page.dart`/`task_create_panel.dart`.
  final String? clientId;
  final String statusId;
  final String observations;
  final DateTime? reminderTime;
  final bool reminderSent;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final int rescheduledCount;
  final String date; // "YYYY-MM-DD"
  final String? groupId;
  final bool visibleToAllGroups;
  final bool isDeleted;
  final DateTime? deletedAt;
  final String? deletedBy;
  final String? deletedByName;
  // Sprint 7.4.1: id of the user who created the task, so onTaskCreate can
  // exclude them from their own "task created" push (e.g. a self-assigned
  // task, or a task in the creator's own group).
  final String? createdBy;

  /// The tenant ("empresa") this task belongs to. See `AppUser.empresaId`.
  final String? empresaId;

  const TaskModel({
    required this.id,
    required this.hour,
    required this.assignedUserId,
    this.taskTypeId,
    required this.clientName,
    required this.clientPhone,
    this.clientId,
    required this.statusId,
    required this.date,
    this.observations = '',
    this.reminderTime,
    this.reminderSent = false,
    this.createdAt,
    this.completedAt,
    this.rescheduledCount = 0,
    this.groupId,
    this.visibleToAllGroups = false,
    this.isDeleted = false,
    this.deletedAt,
    this.deletedBy,
    this.deletedByName,
    this.createdBy,
    this.empresaId,
  });

  /// The full scheduled [DateTime] obtained by combining [date] and [hour].
  DateTime get scheduledDateTime {
    final day = AppDateUtils.parseDateKey(date);
    final parts = hour.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  factory TaskModel.fromMap(String id, Map<String, dynamic> map) {
    return TaskModel(
      id: id,
      hour: map['hour'] as String? ?? '00:00',
      assignedUserId: map['assignedUserId'] as String? ?? '',
      taskTypeId: map['taskTypeId'] as String?,
      clientName: map['clientName'] as String? ?? '',
      clientPhone: map['clientPhone'] as String? ?? '',
      clientId: map['clientId'] as String?,
      statusId: map['statusId'] as String? ?? '',
      observations: map['observations'] as String? ?? '',
      reminderTime: (map['reminderTime'] as Timestamp?)?.toDate(),
      reminderSent: map['reminderSent'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      completedAt: (map['completedAt'] as Timestamp?)?.toDate(),
      rescheduledCount: (map['rescheduledCount'] as num?)?.toInt() ?? 0,
      date: map['date'] as String? ?? '',
      groupId: map['groupId'] as String?,
      visibleToAllGroups: map['visibleToAllGroups'] as bool? ?? false,
      isDeleted: map['isDeleted'] as bool? ?? false,
      deletedAt: (map['deletedAt'] as Timestamp?)?.toDate(),
      deletedBy: map['deletedBy'] as String?,
      deletedByName: map['deletedByName'] as String?,
      createdBy: map['createdBy'] as String?,
      empresaId: map['empresaId'] as String?,
    );
  }

  factory TaskModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return TaskModel.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap({bool withServerTimestamp = false}) {
    return {
      'hour': hour,
      'assignedUserId': assignedUserId,
      'taskTypeId': taskTypeId,
      'clientName': clientName,
      'clientPhone': clientPhone,
      'clientId': clientId,
      'statusId': statusId,
      'observations': observations,
      'reminderTime':
          reminderTime != null ? Timestamp.fromDate(reminderTime!) : null,
      'reminderSent': reminderSent,
      'createdAt': withServerTimestamp
          ? FieldValue.serverTimestamp()
          : (createdAt != null ? Timestamp.fromDate(createdAt!) : null),
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'rescheduledCount': rescheduledCount,
      'date': date,
      'groupId': groupId,
      'visibleToAllGroups': visibleToAllGroups,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'deletedBy': deletedBy,
      'deletedByName': deletedByName,
      'createdBy': createdBy,
      'empresaId': empresaId,
    };
  }

  TaskModel copyWith({
    String? hour,
    String? assignedUserId,
    String? taskTypeId,
    String? clientName,
    String? clientPhone,
    String? clientId,
    bool? clearClientId,
    String? statusId,
    String? observations,
    DateTime? reminderTime,
    bool? clearReminder,
    bool? reminderSent,
    DateTime? completedAt,
    bool? clearCompletedAt,
    int? rescheduledCount,
    String? date,
    String? groupId,
    bool? visibleToAllGroups,
    bool? isDeleted,
    DateTime? deletedAt,
    bool? clearDeletedAt,
    String? deletedBy,
    bool? clearDeletedBy,
    String? deletedByName,
    bool? clearDeletedByName,
    bool? clearTaskTypeId,
  }) {
    return TaskModel(
      id: id,
      hour: hour ?? this.hour,
      assignedUserId: assignedUserId ?? this.assignedUserId,
      taskTypeId: clearTaskTypeId == true ? null : (taskTypeId ?? this.taskTypeId),
      clientName: clientName ?? this.clientName,
      clientPhone: clientPhone ?? this.clientPhone,
      clientId: clearClientId == true ? null : (clientId ?? this.clientId),
      statusId: statusId ?? this.statusId,
      observations: observations ?? this.observations,
      reminderTime: clearReminder == true
          ? null
          : (reminderTime ?? this.reminderTime),
      reminderSent: reminderSent ?? this.reminderSent,
      createdAt: createdAt,
      completedAt:
          clearCompletedAt == true ? null : (completedAt ?? this.completedAt),
      rescheduledCount: rescheduledCount ?? this.rescheduledCount,
      date: date ?? this.date,
      groupId: groupId ?? this.groupId,
      visibleToAllGroups: visibleToAllGroups ?? this.visibleToAllGroups,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt:
          clearDeletedAt == true ? null : (deletedAt ?? this.deletedAt),
      deletedBy:
          clearDeletedBy == true ? null : (deletedBy ?? this.deletedBy),
      deletedByName:
          clearDeletedByName == true ? null : (deletedByName ?? this.deletedByName),
      createdBy: createdBy,
      empresaId: empresaId,
    );
  }
}
