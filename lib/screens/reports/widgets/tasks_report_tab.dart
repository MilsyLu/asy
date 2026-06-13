import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/csv_export.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/task_visibility.dart';
import '../../../models/task_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/catalog_provider.dart';
import '../../../services/task_repository.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 1: full list of tasks registered within the selected range,
/// exportable as CSV.
class TasksReportTab extends StatelessWidget {
  const TasksReportTab({super.key, required this.range});

  final DateTimeRange range;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    final catalog = context.watch<CatalogProvider>();
    final currentUser = context.watch<AuthProvider>().appUser;

    if (currentUser == null) return const LoadingIndicator();

    return StreamBuilder<List<TaskModel>>(
      stream: repo.watchTasksInRange(range.start, range.end),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingIndicator();
        }
        if (snapshot.hasError) {
          return EmptyState(
            message: 'No se pudieron cargar las tareas.\n${snapshot.error}',
            icon: LucideIcons.alertCircle,
          );
        }

        final tasks = (snapshot.data ?? [])
            .where((t) => isTaskVisibleToUser(
                  task: t,
                  user: currentUser,
                  catalog: catalog,
                ))
            .toList()
          ..sort((a, b) {
            final cmp = a.date.compareTo(b.date);
            return cmp != 0 ? cmp : a.hour.compareTo(b.hour);
          });

        if (tasks.isEmpty) {
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
                  onPressed: () => _exportCsv(tasks, catalog),
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
                      DataColumn(label: Text('Encargado')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Reprog.')),
                    ],
                    rows: [
                      for (final t in tasks)
                        DataRow(cells: [
                          DataCell(Text(t.date)),
                          DataCell(Text(t.hour)),
                          DataCell(Text(t.clientName)),
                          DataCell(Text(t.clientPhone)),
                          DataCell(Text(catalog.taskTypeName(t.taskTypeId))),
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
      },
    );
  }

  Future<void> _exportCsv(List<TaskModel> tasks, CatalogProvider catalog) async {
    final rows = <List<dynamic>>[
      ['Fecha', 'Hora', 'Cliente', 'Teléfono', 'Tipo', 'Encargado', 'Estado', 'Reprogramaciones'],
      for (final t in tasks)
        [
          t.date,
          t.hour,
          t.clientName,
          t.clientPhone,
          catalog.taskTypeName(t.taskTypeId),
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
