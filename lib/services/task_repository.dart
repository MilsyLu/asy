import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../core/utils/date_utils.dart';
import '../models/task_model.dart';

/// CRUD + queries for the `tasks` collection.
class TaskRepository {
  TaskRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.tasks);

  /// Tasks scheduled for a single day, ordered by hour.
  Stream<List<TaskModel>> watchTasksForDate(DateTime date) {
    final dateKey = AppDateUtils.formatDateKey(date);
    return _collection
        .where('date', isEqualTo: dateKey)
        .orderBy('hour')
        .snapshots()
        .map((snap) => snap.docs.map((d) => TaskModel.fromDoc(d)).toList());
  }

  /// Tasks scheduled within an inclusive date range (`YYYY-MM-DD` keys),
  /// used by the calendar/week views and reports.
  Stream<List<TaskModel>> watchTasksInRange(DateTime start, DateTime end) {
    final startKey = AppDateUtils.formatDateKey(start);
    final endKey = AppDateUtils.formatDateKey(end);
    return _collection
        .where('date', isGreaterThanOrEqualTo: startKey)
        .where('date', isLessThanOrEqualTo: endKey)
        .orderBy('date')
        .orderBy('hour')
        .snapshots()
        .map((snap) => snap.docs.map((d) => TaskModel.fromDoc(d)).toList());
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
    return snap.docs.map((d) => TaskModel.fromDoc(d)).toList();
  }

  Stream<TaskModel?> watchTask(String taskId) {
    return _collection.doc(taskId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return TaskModel.fromDoc(doc);
    });
  }

  /// Checks whether [assignedUserId] already has a task at [date] + [hour].
  /// Pass [excludeTaskId] when editing to ignore the task being edited.
  Future<bool> hasConflict({
    required String assignedUserId,
    required String date,
    required String hour,
    String? excludeTaskId,
  }) async {
    final snap = await _collection
        .where('assignedUserId', isEqualTo: assignedUserId)
        .where('date', isEqualTo: date)
        .where('hour', isEqualTo: hour)
        .get();
    return snap.docs.any((d) => d.id != excludeTaskId);
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
