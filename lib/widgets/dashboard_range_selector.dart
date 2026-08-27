import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';
import '../providers/dashboard_range_provider.dart';

/// The period selector, drawn wherever it is placed — today, the shell's top
/// bar on the Dashboard.
///
/// Kept as its own widget rather than inside the Dashboard because the control
/// and the screen it drives no longer live together: the state is in
/// [DashboardRangeController] and both read it from there.
class DashboardRangeSelector extends StatelessWidget {
  const DashboardRangeSelector({super.key});

  Future<void> _onChanged(BuildContext context, int index) async {
    final range = context.read<DashboardRangeController>();

    if (index == DashboardRangeController.customIndex) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 3),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: DateTimeRange(start: range.start, end: range.end),
        helpText: 'Elige el periodo',
        saveText: 'Aplicar',
      );
      if (picked == null) return;
      range.select(DashboardRangeController.customIndex, custom: picked);
      return;
    }

    range.select(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final range = context.watch<DashboardRangeController>();

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: range.index,
          isDense: true,
          icon: Icon(LucideIcons.chevronDown, size: 16, color: colors.textSecondary),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          dropdownColor: colors.surface,
          style: TextStyle(color: colors.textPrimary, fontSize: 13),
          // Closed it shows the real period, so a custom range reads as the
          // dates it covers instead of the word "Personalizado".
          selectedItemBuilder: (context) => [
            for (var i = 0; i < DashboardRangeController.labels.length; i++)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  range.label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
          items: [
            for (var i = 0; i < DashboardRangeController.labels.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(DashboardRangeController.labels[i]),
              ),
          ],
          onChanged: (i) => i == null ? null : _onChanged(context, i),
        ),
      ),
    );
  }
}
