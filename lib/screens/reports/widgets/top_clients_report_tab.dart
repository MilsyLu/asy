import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/task_visibility.dart';
import '../../../models/task_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/catalog_provider.dart';
import '../../../services/task_repository.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 5: top 10 clients by completed "Instalación" tasks within the
/// selected range.
class TopClientsReportTab extends StatelessWidget {
  const TopClientsReportTab({super.key, required this.range});

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

        final completedId = catalog.completedStatusId;
        final installationTypeId = catalog.taskTypeByName(AppTaskTypeNames.instalacion)?.id;

        final tasks = (snapshot.data ?? [])
            .where((t) => isTaskVisibleToUser(
                  task: t,
                  user: currentUser,
                  catalog: catalog,
                ))
            .where((t) => t.statusId == completedId && t.taskTypeId == installationTypeId)
            .toList();

        if (tasks.isEmpty) {
          return const EmptyState(
            message: 'No hay instalaciones completadas en el rango seleccionado.',
            icon: LucideIcons.award,
          );
        }

        final counts = <String, _ClientCount>{};
        for (final t in tasks) {
          final key = '${t.clientName}|${t.clientPhone}';
          counts.putIfAbsent(key, () => _ClientCount(t.clientName, t.clientPhone)).count++;
        }

        final top10 = counts.values.toList()
          ..sort((a, b) => b.count.compareTo(a.count));
        final top = top10.take(10).toList();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: top.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final c = top[index];
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.2)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.background,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(c.clientName, style: const TextStyle(color: AppColors.textPrimary)),
                subtitle: Text(
                  c.clientPhone,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                trailing: Text(
                  c.count == 1 ? '1 instalación' : '${c.count} instalaciones',
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w600),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ClientCount {
  _ClientCount(this.clientName, this.clientPhone);

  final String clientName;
  final String clientPhone;
  int count = 0;
}
