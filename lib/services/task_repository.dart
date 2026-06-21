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

/// CRUD + queries for the `tasks` collection.
class TaskRepository {
  TaskRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.tasks);

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

  /// Same as [getTasksInRange] but filtered server-side to a single
  /// [userId] (Sprint 7.4.5 Objetivo 2) — used for scheduling local
  /// reminders, which only ever fire for tasks assigned to the signed-in
  /// user on this device, so there's no reason to download every other
  /// user's tasks in the window just to discard them client-side.
  /// Requires a composite index (assignedUserId ASC, date ASC, hour ASC).
  Future<List<TaskModel>> getTasksForUserInRange(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    final startKey = AppDateUtils.formatDateKey(start);
    final endKey = AppDateUtils.formatDateKey(end);
    final snap = await _collection
        .where('assignedUserId', isEqualTo: userId)
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
    return _collection.doc(taskId).snapshots().map((doc) {
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
    final doc = await _collection.add(task.toMap(withServerTimestamp: true));
    return doc.id;
  }

  Future<void> updateTask(String taskId, Map<String, dynamic> data) {
    return _collection.doc(taskId).update(data);
  }

  Future<void> deleteTask(String taskId) {
    return _collection.doc(taskId).delete();
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

  // -------------------------------------------------------------------------
  // Trash-bin operations
  // -------------------------------------------------------------------------

  /// Marks a task as deleted without removing it from Firestore.
  Future<void> softDeleteTask(
      String taskId, String deletedBy, String deletedByName) {
    return _collection.doc(taskId).update({
      'isDeleted': true,
      'deletedAt': Timestamp.fromDate(DateTime.now()),
      'deletedBy': deletedBy,
      'deletedByName': deletedByName,
    });
  }

  /// Restores a soft-deleted task, clearing all deletion metadata.
  Future<void> restoreTask(String taskId) {
    return _collection.doc(taskId).update({
      'isDeleted': false,
      'deletedAt': FieldValue.delete(),
      'deletedBy': FieldValue.delete(),
      'deletedByName': FieldValue.delete(),
    });
  }

  /// Permanently removes a task document from Firestore (irreversible).
  Future<void> permanentlyDeleteTask(String taskId) {
    return _collection.doc(taskId).delete();
  }

  /// Stream of all soft-deleted tasks, ordered by deletion date (newest first).
  /// Requires composite index (isDeleted ASC, deletedAt DESC) — deploy before
  /// enabling the trash-bin screen in Sprint 2.
  Stream<List<TaskModel>> watchDeletedTasks() {
    return _collection
        .where('isDeleted', isEqualTo: true)
        .orderBy('deletedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => TaskModel.fromDoc(d)).toList());
  }

  /// Stream of soft-deleted tasks within an inclusive date range.
  /// Requires composite index (isDeleted ASC, date ASC) — deploy before
  /// enabling the trash-bin screen in Sprint 2.
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
    return _collection.doc(taskId).update({
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
    return _collection.doc(taskId).update({
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
