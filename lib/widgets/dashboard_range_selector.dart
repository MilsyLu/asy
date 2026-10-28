import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';
import '../providers/dashboard_range_provider.dart';
import 'calendario_menu.dart';

/// The period selector, drawn wherever it is placed — today, the shell's top
/// bar on the Dashboard.
///
/// Kept as its own widget rather than inside the Dashboard because the control
/// and the screen it drives no longer live together: the state is in
/// [DashboardRangeController] and both read it from there.
class DashboardRangeSelector extends StatefulWidget {
  const DashboardRangeSelector({super.key});

  @override
  State<DashboardRangeSelector> createState() => _DashboardRangeSelectorState();
}

class _DashboardRangeSelectorState extends State<DashboardRangeSelector> {
  /// Para abrir el calendario desde el propio desplegable.
  final _menu = MenuController();

  void _onChanged(BuildContext context, int index) {
    final range = context.read<DashboardRangeController>();

    // "Personalizado" despliega el calendario pegado al desplegable, en vez
    // de abrir una ventana a pantalla completa como antes.
    if (index == DashboardRangeController.customIndex) {
      // Al siguiente cuadro: en este instante el desplegable todavía se
      // está cerrando, y abrir el calendario encima se pierde.
      WidgetsBinding.instance.addPostFrameCallback((_) => _menu.open());
      return;
    }

    range.select(index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final range = context.watch<DashboardRangeController>();
    final hoy = DateTime.now();

    return CalendarioRangoMenu(
      controller: _menu,
      rango: DateTimeRange(start: range.start, end: range.end),
      ultimoDia: DateTime(hoy.year, hoy.month, hoy.day),
      onChanged: (r) =>
          range.select(DashboardRangeController.customIndex, custom: r),
      builder: (context, _) => Container(
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
            icon: Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: colors.textSecondary,
            ),
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
      ),
    );
  }
}
