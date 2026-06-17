import 'package:flutter/material.dart';

/// Small pill showing a task type's name tinted with its configured color
/// (Sprint 5.5's shared visual language for task types). Used by Home,
/// the task detail dialog and the trash list so the type's color stays a
/// consistent visual reference across the app instead of plain text.
class TaskTypeChip extends StatelessWidget {
  const TaskTypeChip({
    super.key,
    required this.label,
    required this.color,
    this.dense = false,
  });

  final String label;
  final Color color;

  /// Compact sizing for list rows where vertical space is tight.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 2 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: dense ? 6 : 8,
            height: dense ? 6 : 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: dense ? 5 : 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: dense ? 11 : 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
