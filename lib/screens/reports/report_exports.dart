import '../../core/utils/csv_export.dart';
import '../../core/utils/date_utils.dart';
import '../../models/task_model.dart';
import '../../providers/catalog_provider.dart';

/// Everything the Reportes screen can hand to the user as a file.
///
/// Lives outside the tabs because the export buttons moved up into the header:
/// they act on the filtered list the whole screen is showing, not on whichever
/// tab happens to be open. Excel and PDF will land here too.
Future<void> exportTasksCsv({
  required List<TaskModel> tasks,
  required CatalogProvider catalog,
  required DateTime start,
  required DateTime end,
}) {
  final rows = <List<dynamic>>[
    [
      'Fecha',
      'Hora',
      'Cliente',
      'Teléfono',
      'Tipo',
      'Equipo',
      'Encargado',
      'Estado',
      'Reprogramaciones',
    ],
    for (final t in tasks)
      [
        t.date,
        t.hour,
        t.clientName,
        t.clientPhone,
        catalog.taskTypeName(t.taskTypeId),
        catalog.groupName(t.groupId),
        catalog.userName(t.assignedUserId),
        catalog.statusName(t.statusId),
        t.rescheduledCount,
      ],
  ];

  return exportAndShareCsv(
    fileName:
        'tareas_${AppDateUtils.formatDateKey(start)}_a_${AppDateUtils.formatDateKey(end)}.csv',
    rows: rows,
  );
}

/// The task list in the order a person reads it: by day, then by hour.
List<TaskModel> sortedForReport(List<TaskModel> tasks) {
  return List<TaskModel>.from(tasks)..sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.hour.compareTo(b.hour);
  });
}
