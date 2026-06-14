import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../models/app_user.dart';
import '../../../providers/catalog_provider.dart';
import '../../../widgets/loading_indicator.dart';

/// Report 4: every user ranked by current login streak.
class StreakReportTab extends StatelessWidget {
  const StreakReportTab({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final colors = context.colors;
    final users = List<AppUser>.from(catalog.users)
      ..sort((a, b) => b.streakDays.compareTo(a.streakDays));

    if (users.isEmpty) {
      return const EmptyState(
        message: 'No hay usuarios registrados.',
        icon: LucideIcons.flame,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = users[index];
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colors.background,
              child: Text(
                '${index + 1}',
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(user.name, style: TextStyle(color: colors.textPrimary)),
            subtitle: Text(
              '${user.email}\nÚltimo ingreso: ${AppDateUtils.formatDateTimeOrDash(user.lastLogin)}',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.flame, color: colors.primary, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${user.streakDays}',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Mejor: ${user.maxStreakDays}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
