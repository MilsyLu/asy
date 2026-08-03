import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/constants/support_case_constants.dart';
import 'task_type_chip.dart';

/// Colored pill for a case's priority — thin wrapper over [TaskTypeChip]
/// so every priority badge in the module looks identical without repeating
/// `SupportCasePriority.colorFor(...)` at every call site.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority, this.dense = false});

  final String priority;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return TaskTypeChip(label: priority, color: SupportCasePriority.colorFor(priority), dense: dense);
  }
}

/// Colored pill for a case's status.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.dense = false});

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return TaskTypeChip(label: status, color: SupportCaseStatus.colorFor(status), dense: dense);
  }
}

/// "Días sin resolver" badge — colored by [colorForDaysOpen], with a fire
/// icon once it's badly overdue (Michel's own "🔥 12 días sin resolver"
/// example). [resolved] freezes the wording ("resuelto en X días") instead
/// of implying it's still open.
class DaysOpenBadge extends StatelessWidget {
  const DaysOpenBadge({super.key, required this.days, this.resolved = false, this.dense = false});

  final int days;
  final bool resolved;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = colorForDaysOpen(days);
    final label = resolved
        ? 'Resuelto en $days ${days == 1 ? 'día' : 'días'}'
        : '$days ${days == 1 ? 'día' : 'días'}';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 2 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!resolved && days > 10)
            Icon(LucideIcons.flame, size: dense ? 11 : 13, color: color)
          else
            Icon(LucideIcons.clock, size: dense ? 11 : 13, color: color),
          SizedBox(width: dense ? 4 : 6),
          Text(
            label,
            style: TextStyle(color: color, fontSize: dense ? 11 : 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
