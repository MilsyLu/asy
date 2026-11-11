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
    this.tareas = const [],
  });

  final int total;
  final int completed;
  final int rescheduled;

  /// Las tareas del cliente, de la más reciente a la más vieja.
  ///
  /// La consulta ya las traía enteras y sólo se quedaba con tres cifras.
  /// Tres cifras dicen cuántas veces se le atendió, pero no **cuándo**, que
  /// es lo que uno busca cuando un cliente pregunta "¿y lo de la vez
  /// pasada?".
  final List<TaskModel> tareas;

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
        .map(
          (snap) => snap.docs
              .map((d) => TaskModel.fromDoc(d))
              .where((t) => !t.isDeleted)
              .toList(),
        );
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
        .map(
          (snap) => snap.docs
              .map((d) => TaskModel.fromDoc(d))
              .where((t) => !t.isDeleted)
              .toList(),
        );
  }

  /// Las tareas **asignadas** dentro del rango, sin importar para cuándo
  /// quedaron.
  ///
  /// Contraparte de [watchTasksInRange], que va por la fecha de la tarea.
  /// Son dos preguntas distintas: "qué hay el martes" y "qué mandé el
  /// martes" — y quien asigna el lunes trabajo para toda la semana no
  /// encuentra lo suyo mirando por fecha de la tarea.
  ///
  /// [end] se lleva al final del día: un rango que termina el martes tiene
  /// que incluir lo asignado el martes a las 4 de la tarde, y `createdAt`
  /// lleva la hora, a diferencia de `date`.
  Stream<List<TaskModel>> watchTasksCreatedInRange(
    DateTime start,
    DateTime end,
  ) {
    final desde = DateTime(start.year, start.month, start.day);
    final hasta = DateTime(end.year, end.month, end.day, 23, 59, 59, 999);
    return _collection
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(hasta))
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => TaskModel.fromDoc(d))
              .where((t) => !t.isDeleted)
              .toList(),
        );
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
    final data = task.toMap(withServerTimestamp: true)
      ..['empresaId'] = empresaId;
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
    final snap = await _collection
        .where('assignedUserId', isEqualTo: userId)
        .get();
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
    // Lo que está en la papelera no cuenta: seguía sumando en los tres
    // números, así que la ficha decía que un cliente tenía tareas que ya
    // nadie ve en ninguna pantalla.
    final tareas = [
      for (final d in snap.docs)
        if (!(d.data()['isDeleted'] as bool? ?? false)) TaskModel.fromDoc(d),
    ]..sort((a, b) => b.scheduledDateTime.compareTo(a.scheduledDateTime));

    var completed = 0;
    var rescheduled = 0;
    for (final t in tareas) {
      if (completedStatusId != null && t.statusId == completedStatusId) {
        completed++;
      }
      if (rescheduledStatusId != null && t.statusId == rescheduledStatusId) {
        rescheduled++;
      }
    }
    return ClientTaskHistory(
      total: tareas.length,
      completed: completed,
      rescheduled: rescheduled,
      tareas: tareas,
    );
  }

  // -------------------------------------------------------------------------
  // Trash-bin operations
  // -------------------------------------------------------------------------

  /// Marks a task as deleted without removing it from Firestore.
  Future<void> softDeleteTask(
    String taskId,
    String deletedBy,
    String deletedByName,
  ) {
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

  /// Permanently deletes several already-soft-deleted tasks at once — used
  /// by Papelera's "Eliminar todas" (applies to whatever's currently
  /// filtered/visible, not necessarily every trashed task ever). Firestore
  /// batches cap at 500 writes, so [taskIds] is chunked defensively even
  /// though Papelera realistically never holds that many at once.
  Future<void> permanentlyDeleteTasks(List<String> taskIds) async {
    const chunkSize = 400;
    for (var i = 0; i < taskIds.length; i += chunkSize) {
      final end = i + chunkSize > taskIds.length
          ? taskIds.length
          : i + chunkSize;
      final chunk = taskIds.sublist(i, end);
      final batch = _firestore.batch();
      for (final id in chunk) {
        batch.delete(_tasksCollection.doc(id));
      }
      await batch.commit();
    }
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
    DateTime start,
    DateTime end,
  ) {
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

  /// Marca la tarea como completada, dejando dicho quién lo hizo.
  ///
  /// [completedBy] es quien está usando la app en ese momento, que no
  /// siempre es el encargado: un administrador puede marcar la tarea de
  /// otro. Sin este dato, un aviso sólo podía suponer que fue el
  /// encargado — y daría por hecho algo falso cada vez que no lo fuera.
  Future<void> completeTask(
    String taskId,
    String completedStatusId, {
    required String? completedBy,
  }) {
    return _tasksCollection.doc(taskId).update({
      'statusId': completedStatusId,
      'completedAt': Timestamp.fromDate(DateTime.now()),
      'completedBy': completedBy,
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
    required String? rescheduledBy,
    required String previousDate,
    required String previousHour,
    DateTime? reminderTime,
    bool clearReminder = false,
  }) {
    return _tasksCollection.doc(taskId).update({
      'date': newDate,
      'hour': newHour,
      // De dónde venía, antes de que las dos líneas de arriba lo borren. Es
      // lo único que permite responder "¿y qué fecha tenía antes?", que hasta
      // ahora no tenía respuesta en ninguna parte.
      'rescheduleHistory': FieldValue.arrayUnion([
        {
          'fromDate': previousDate,
          'fromHour': previousHour,
          'at': Timestamp.fromDate(DateTime.now()),
          'by': rescheduledBy,
        },
      ]),
      'statusId': rescheduledStatusId,
      'rescheduledCount': currentRescheduledCount + 1,
      // Required (though nullable): this repository has no access to the
      // signed-in user, so only the caller can supply it. Always written,
      // even when null — leaving the field out would keep whatever previous
      // value the document held, and the notification would then credit the
      // wrong person for this reschedule.
      'updatedBy': rescheduledBy,
      'reminderSent': false,
      'reminderTime': clearReminder
          ? null
          : (reminderTime != null ? Timestamp.fromDate(reminderTime) : null),
    });
  }
}
