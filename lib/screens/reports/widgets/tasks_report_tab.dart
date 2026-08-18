import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 1: the task list itself.
///
/// [tasks] arrives already loaded, visibility-filtered, narrowed by the header
/// filters and sorted — this tab only draws it. The export button used to live
/// here; it moved to the header, where it acts on the same filtered list no
/// matter which tab is open.
class TasksReportTab extends StatelessWidget {
  const TasksReportTab({super.key, required this.tasks});

  final List<TaskModel> tasks;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final sorted = tasks;

    if (sorted.isEmpty) {
      return const EmptyState(
        message: 'No hay tareas registradas en el rango seleccionado.',
        icon: LucideIcons.clipboardList,
      );
    }

    return Column(
      children: [
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
                    DataRow(
                      cells: [
                        DataCell(Text(t.date)),
                        DataCell(Text(t.hour)),
                        DataCell(Text(t.clientName)),
                        DataCell(Text(t.clientPhone)),
                        DataCell(Text(catalog.taskTypeName(t.taskTypeId))),
                        DataCell(Text(catalog.groupName(t.groupId))),
                        DataCell(Text(catalog.userName(t.assignedUserId))),
                        DataCell(Text(catalog.statusName(t.statusId))),
                        DataCell(Text('${t.rescheduledCount}')),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
