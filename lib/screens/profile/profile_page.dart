import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/auth_service.dart';
import '../../services/task_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../home/widgets/task_card.dart';

/// Profile tab: account info, streak stats and the user's upcoming tasks.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final catalog = context.watch<CatalogProvider>();
    final repo = context.read<TaskRepository>();
    final user = auth.appUser;

    if (user == null) {
      return const Scaffold(body: LoadingIndicator());
    }

    final today = DateTime.now();
    final rangeEnd = today.add(const Duration(days: 14));

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.gold, width: 2),
                  ),
                  child: const Icon(LucideIcons.userCircle, color: AppColors.gold, size: 40),
                ),
                const SizedBox(height: 12),
                Text(
                  user.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _InfoChip(
                      icon: LucideIcons.userCheck,
                      label: AuthService.roleLabel(user.role),
                    ),
                    if (user.groupId != null)
                      _InfoChip(
                        icon: LucideIcons.users,
                        label: catalog.groupName(user.groupId),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.flame,
                  label: 'Racha actual',
                  value: '${user.streakDays}',
                  suffix: user.streakDays == 1 ? 'día' : 'días',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: LucideIcons.barChart3,
                  label: 'Mejor racha',
                  value: '${user.maxStreakDays}',
                  suffix: user.maxStreakDays == 1 ? 'día' : 'días',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.clock, color: AppColors.gold, size: 18),
                const SizedBox(width: 10),
                Text(
                  'Último ingreso: ',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                Text(
                  AppDateUtils.formatDateTimeOrDash(user.lastLogin),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: const [
              Icon(LucideIcons.listChecks, color: AppColors.gold, size: 18),
              SizedBox(width: 8),
              Text(
                'Próximas tareas',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<TaskModel>>(
            stream: repo.watchTasksInRange(today, rangeEnd),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: LoadingIndicator(),
                );
              }

              final pendingId = catalog.pendingStatusId;
              final upcoming = (snapshot.data ?? [])
                  .where((t) =>
                      t.assignedUserId == user.id &&
                      t.statusId != catalog.completedStatusId &&
                      (t.date != AppDateUtils.formatDateKey(today) ||
                          t.statusId == pendingId ||
                          t.statusId == catalog.rescheduledStatusId))
                  .toList()
                ..sort((a, b) {
                  final cmp = a.date.compareTo(b.date);
                  return cmp != 0 ? cmp : a.hour.compareTo(b.hour);
                });

              final limited = upcoming.take(5).toList();

              if (limited.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: EmptyState(
                    message: 'No tienes tareas próximas pendientes.',
                    icon: LucideIcons.calendarDays,
                  ),
                );
              }

              return Column(
                children: [
                  for (final task in limited) TaskCard(task: task),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showConfirmDialog(
                context,
                title: 'Cerrar sesión',
                message: '¿Estás seguro que deseas cerrar sesión?',
                confirmLabel: 'Cerrar sesión',
                destructive: true,
              );
              if (confirm && context.mounted) {
                try {
                  await context.read<AuthProvider>().signOut();
                } catch (e) {
                  if (context.mounted) {
                    SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
                  }
                }
              }
            },
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            icon: const Icon(LucideIcons.logOut),
            label: const Text('Cerrar sesión'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.suffix,
  });

  final IconData icon;
  final String label;
  final String value;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.gold, size: 16),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.gold,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Text(suffix, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
