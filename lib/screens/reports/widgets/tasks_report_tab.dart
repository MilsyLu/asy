import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/csv_export.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 1: full list of tasks registered within the selected range,
/// exportable as CSV. [tasks] is the already-loaded, visibility-filtered
/// list shared by every report tab (lifted to `ReportsPage` — Sprint 6.1
/// Part 7 — so this tab doesn't open its own Firestore listener).
class TasksReportTab extends StatelessWidget {
  const TasksReportTab({super.key, required this.tasks, required this.range});

  final List<TaskModel> tasks;
  final DateTimeRange range;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();

    final sorted = List<TaskModel>.from(tasks)
      ..sort((a, b) {
        final cmp = a.date.compareTo(b.date);
        return cmp != 0 ? cmp : a.hour.compareTo(b.hour);
      });

    if (sorted.isEmpty) {
      return const EmptyState(
        message: 'No hay tareas registradas en el rango seleccionado.',
        icon: LucideIcons.clipboardList,
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => _exportCsv(sorted, catalog),
              icon: const Icon(LucideIcons.download, size: 16),
              label: const Text('Exportar CSV'),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Fecha')),
                  DataColumn(label: Text('Hora')),
                  DataColumn(label: Text('Cliente')),
                  DataColumn(label: Text('Teléfono')),
                  DataColumn(label: Text('Tipo')),
                  DataColumn(label: Text('Equipo')),
                  DataColumn(label: Text('Encargado')),
                  DataColumn(label: Text('Estado')),
                  DataColumn(label: Text('Reprog.')),
                ],
                rows: [
                  for (final t in sorted)
                    DataRow(cells: [
                      DataCell(Text(t.date)),
                      DataCell(Text(t.hour)),
                      DataCell(Text(t.clientName)),
                      DataCell(Text(t.clientPhone)),
                      DataCell(Text(catalog.taskTypeName(t.taskTypeId))),
                      DataCell(Text(catalog.groupName(t.groupId))),
                      DataCell(Text(catalog.userName(t.assignedUserId))),
                      DataCell(Text(catalog.statusName(t.statusId))),
                      DataCell(Text('${t.rescheduledCount}')),
                    ]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _exportCsv(List<TaskModel> tasks, CatalogProvider catalog) async {
    final rows = <List<dynamic>>[
      ['Fecha', 'Hora', 'Cliente', 'Teléfono', 'Tipo', 'Equipo', 'Encargado', 'Estado', 'Reprogramaciones'],
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
    final fileName =
        'tareas_${AppDateUtils.formatDateKey(range.start)}_a_${AppDateUtils.formatDateKey(range.end)}.csv';
    await exportAndShareCsv(fileName: fileName, rows: rows);
  }
}
