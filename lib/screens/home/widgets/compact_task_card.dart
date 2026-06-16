import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';

/// Compact single-task card for the Calendar day-list view.
///
/// Visual layout (top → bottom):
///   1. Hour (accent color) + status chip (right-aligned)
///   2. Client name — largest, most prominent
///   3. Task type · assignee — secondary, muted
///
/// The left accent strip encodes the task status at a glance:
///   amber → Pendiente, green → Completada, blue → Reprogramada, grey → other.
/// Pass [accentColor] to override (e.g. [AppColorsExtension.error] for overdue).
///
/// Gestures are not wired inside — the caller handles onTap / onLongPress.
class CompactTaskCard extends StatelessWidget {
  const CompactTaskCard({super.key, required this.task, this.accentColor});

  final TaskModel task;

  /// Overrides the status-derived accent color for the strip, hour and chip.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final colors = context.colors;
    final statusName = catalog.statusName(task.statusId);
    final accent = accentColor ?? taskStatusColor(colors, statusName);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.divider),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colored left strip — status at a glance.
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hour + status chip.
                    Row(
                      children: [
                        Icon(LucideIcons.clock, size: 13, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          task.hour,
                          style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        _CompactStatusChip(statusName: statusName, color: accent),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Client name — most prominent.
                    Text(
                      task.clientName,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    // Type · Assignee.
                    Row(
                      children: [
                        Icon(LucideIcons.tag, size: 12, color: colors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${catalog.taskTypeName(task.taskTypeId)} · ${catalog.userName(task.assignedUserId)}',
                            style: TextStyle(color: colors.textSecondary, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactStatusChip extends StatelessWidget {
  const _CompactStatusChip({required this.statusName, required this.color});

  final String statusName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        statusName,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Maps a status name to its semantic accent color from [AppColorsExtension].
///
/// Consistent with the palette used in Home's agenda sections:
///   Pendiente → amber, Completada → green, Reprogramada → blue, other → grey.
///
/// Exported so Calendar and Week views can share the same mapping without
/// duplicating logic.
Color taskStatusColor(AppColorsExtension colors, String statusName) {
  final lower = statusName.toLowerCase();
  if (lower == AppStatusNames.pendiente.toLowerCase()) return colors.statusPending;
  if (lower == AppStatusNames.completada.toLowerCase()) return colors.success;
  if (lower == AppStatusNames.reprogramada.toLowerCase()) return colors.statusRescheduled;
  return colors.textSecondary;
}
