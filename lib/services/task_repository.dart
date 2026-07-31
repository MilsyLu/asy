import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../core/utils/date_utils.dart';
import '../models/task_model.dart';

/// Snapshot of how many tasks have ever been assigned to a user, broken
/// down by status. Used by the admin "Eliminar permanentemente" flow
/// (Sprint 7.3.1) to decide whether deleting the user is safe.
class UserTaskHistory {
  const UserTaskHistory({
    required this.assigned,
    required this.completed,
    required this.rescheduled,
  });

  final int assigned;
  final int completed;
  final int rescheduled;

  bool get hasHistory => assigned > 0;
}

/// Same shape as [UserTaskHistory] but for a client — used by the
/// "Eliminar" flow in `clients_page.dart` to decide whether deleting a
/// client is safe, and to show a quick history summary in its detail sheet.
class ClientTaskHistory {
  const ClientTaskHistory({
    required this.total,
    required this.completed,
    required this.rescheduled,
  });

  final int total;
  final int completed;
  final int rescheduled;

  bool get hasHistory => total > 0;
}

/// CRUD + queries for the `tasks` collection.
///
/// Multi-tenant: every read is pre-filtered to [empresaId] at the query
/// level, and every write stamps `empresaId` into the document —
/// firestore.rules independently re-verifies this (see `sameEmpresa()`).
class TaskRepository {
  TaskRepository({required this.empresaId, FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String empresaId;

  CollectionReference<Map<String, dynamic>> get _tasksCollection =>
      _firestore.collection(FirestoreCollections.tasks);

  Query<Map<String, dynamic>> get _collection =>
      _tasksCollection.where('empresaId', isEqualTo: empresaId);

  /// Tasks scheduled for a single day, ordered by hour.
  /// Soft-deleted tasks are excluded client-side (no index change required).
  Stream<List<TaskModel>> watchTasksForDate(DateTime date) {
    final dateKey = AppDateUtils.formatDateKey(date);
    return _collection
        .where('date', isEqualTo: dateKey)
        .orderBy('hour')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TaskModel.fromDoc(d))
            .where((t) => !t.isDeleted)
            .toList());
  }

  /// Tasks scheduled within an inclusive date range (`YYYY-MM-DD` keys),
  /// used by the calendar/week views and reports.
  /// Soft-deleted tasks are excluded client-side.
  Stream<List<TaskModel>> watchTasksInRange(DateTime start, DateTime end) {
    final startKey = AppDateUtils.formatDateKey(start);
    final endKey = AppDateUtils.formatDateKey(end);
    return _collection
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .orderBy('date')
        .orderBy('hour')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => TaskModel.fromDoc(d))
            .where((t) => !t.isDeleted)
            .toList());
  }

  Future<List<TaskModel>> getTasksInRange(DateTime start, DateTime end) async {
    final startKey = AppDateUtils.formatDateKey(start);
    final endKey = AppDateUtils.formatDateKey(end);
    final snap = await _collection
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .orderBy('date')
        .orderBy('hour')
        .get();
    return snap.docs
        .map((d) => TaskModel.fromDoc(d))
        .where((t) => !t.isDeleted)
        .toList();
  }

  Stream<TaskModel?> watchTask(String taskId) {
    return _tasksCollection.doc(taskId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return TaskModel.fromDoc(doc);
    });
  }

  /// Checks whether [assignedUserId] already has a task at [date] + [hour].
  /// Pass [excludeTaskId] when editing to ignore the task being edited, and
  /// [ignoreStatusIds] to skip tasks in statuses that shouldn't count as a
  /// conflict (e.g. "Completada" or "Cancelada").
  Future<bool> hasConflict({
    required String assignedUserId,
    required String date,
    required String hour,
    String? excludeTaskId,
    List<String>? ignoreStatusIds,
  }) async {
    final snap = await _collection
        .where('assignedUserId', isEqualTo: assignedUserId)
        .where('date', isEqualTo: date)
        .where('hour', isEqualTo: hour)
        .get();
    return snap.docs.any((d) {
      if (d.id == excludeTaskId) return false;
      if (d.data()['isDeleted'] == true) return false;
      if (ignoreStatusIds != null &&
          ignoreStatusIds.contains(d.data()['statusId'])) {
        return false;
      }
      return true;
    });
  }

  Future<String> createTask(TaskModel task) async {
    final data = task.toMap(withServerTimestamp: true)..['empresaId'] = empresaId;
    final doc = await _tasksCollection.add(data);
    return doc.id;
  }

  Future<void> updateTask(String taskId, Map<String, dynamic> data) {
    return _tasksCollection.doc(taskId).update(data);
  }

  Future<void> deleteTask(String taskId) {
    return _tasksCollection.doc(taskId).delete();
  }

  /// Counts every task ever assigned to [userId] — including soft-deleted
  /// (papelera) ones, since historical data must be preserved regardless of
  /// trash state — broken down by completed/rescheduled status. Used to
  /// decide whether permanently deleting a user is safe (Sprint 7.3.1).
  Future<UserTaskHistory> getUserTaskHistory(
    String userId, {
    String? completedStatusId,
    String? rescheduledStatusId,
  }) async {
    final snap =
        await _collection.where('assignedUserId', isEqualTo: userId).get();
    var completed = 0;
    var rescheduled = 0;
    for (final doc in snap.docs) {
      final statusId = doc.data()['statusId'] as String?;
      if (completedStatusId != null && statusId == completedStatusId) {
        completed++;
      }
      if (rescheduledStatusId != null && statusId == rescheduledStatusId) {
        rescheduled++;
      }
    }
    return UserTaskHistory(
      assigned: snap.docs.length,
      completed: completed,
      rescheduled: rescheduled,
    );
  }

  /// Same as [getUserTaskHistory] but keyed by `clientId` instead of
  /// `assignedUserId` — includes soft-deleted tasks for the same reason
  /// (historical data must be preserved regardless of trash state).
  Future<ClientTaskHistory> getClientTaskHistory(
    String clientId, {
    String? completedStatusId,
    String? rescheduledStatusId,
  }) async {
    final snap = await _collection.where('clientId', isEqualTo: clientId).get();
    var completed = 0;
    var rescheduled = 0;
    for (final doc in snap.docs) {
      final statusId = doc.data()['statusId'] as String?;
      if (completedStatusId != null && statusId == completedStatusId) {
        completed++;
      }
      if (rescheduledStatusId != null && statusId == rescheduledStatusId) {
        rescheduled++;
      }
    }
    return ClientTaskHistory(
      total: snap.docs.length,
      completed: completed,
      rescheduled: rescheduled,
    );
  }

  // -------------------------------------------------------------------------
  // Trash-bin operations
  // -------------------------------------------------------------------------

  /// Marks a task as deleted without removing it from Firestore.
  Future<void> softDeleteTask(
      String taskId, String deletedBy, String deletedByName) {
    return _tasksCollection.doc(taskId).update({
      'isDeleted': true,
      'deletedAt': Timestamp.fromDate(DateTime.now()),
      'deletedBy': deletedBy,
      'deletedByName': deletedByName,
    });
  }

  /// Restores a soft-deleted task, clearing all deletion metadata.
  Future<void> restoreTask(String taskId) {
    return _tasksCollection.doc(taskId).update({
      'isDeleted': false,
      'deletedAt': FieldValue.delete(),
      'deletedBy': FieldValue.delete(),
      'deletedByName': FieldValue.delete(),
    });
  }

  /// Permanently removes a task document from Firestore (irreversible).
  Future<void> permanentlyDeleteTask(String taskId) {
    return _tasksCollection.doc(taskId).delete();
  }

  /// Stream of all soft-deleted tasks, ordered by deletion date (newest first).
  /// Requires composite index (empresaId ASC, isDeleted ASC, deletedAt DESC).
  Stream<List<TaskModel>> watchDeletedTasks() {
    return _collection
        .where('isDeleted', isEqualTo: true)
        .orderBy('deletedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => TaskModel.fromDoc(d)).toList());
  }

  /// Stream of soft-deleted tasks within an inclusive date range.
  /// Requires composite index (empresaId ASC, isDeleted ASC, date ASC).
  Stream<List<TaskModel>> watchDeletedTasksByDateRange(
      DateTime start, DateTime end) {
    final startKey = AppDateUtils.formatDateKey(start);
    final endKey = AppDateUtils.formatDateKey(end);
    return _collection
        .where('isDeleted', isEqualTo: true)
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map((d) => TaskModel.fromDoc(d)).toList());
  }

  /// Marks a task as completed by the worker.
  Future<void> completeTask(String taskId, String completedStatusId) {
    return _tasksCollection.doc(taskId).update({
      'statusId': completedStatusId,
      'completedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Reschedules a task to a new date/hour, bumping `rescheduledCount`
  /// and setting the status to "Reprogramada".
  Future<void> rescheduleTask({
    required String taskId,
    required String newDate,
    required String newHour,
    required String rescheduledStatusId,
    required int currentRescheduledCount,
    DateTime? reminderTime,
    bool clearReminder = false,
  }) {
    return _tasksCollection.doc(taskId).update({
      'date': newDate,
      'hour': newHour,
      'statusId': rescheduledStatusId,
      'rescheduledCount': currentRescheduledCount + 1,
      'reminderSent': false,
      'reminderTime': clearReminder
          ? null
          : (reminderTime != null ? Timestamp.fromDate(reminderTime) : null),
    });
  }
}
