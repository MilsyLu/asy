import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/responsive/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/report_filters.dart';
import '../../../models/task_model.dart';
import '../../../providers/catalog_provider.dart';

/// The whole first row of Reportes: period, search, and the four narrowings.
///
/// The options are built from the tasks actually loaded, not from the full
/// catalogue. Two reasons: a filter can never come up empty, and a team
/// administrator is never offered teams they cannot see — the visibility rules
/// have already been applied by the time this list arrives, so nothing here
/// has to re-implement them.
class ReportFilterBar extends StatefulWidget {
  const ReportFilterBar({
    super.key,
    required this.filters,
    required this.onChanged,
    required this.tasks,
    required this.catalog,
    required this.matchCount,
    required this.dateSelector,
  });

  final ReportFilters filters;
  final ValueChanged<ReportFilters> onChanged;

  /// Everything in range and visible, before these filters are applied.
  final List<TaskModel> tasks;

  final CatalogProvider catalog;

  /// How many survive the current filters — the second half of "12 de 44".
  final int matchCount;

  /// The date-range button, laid out here so the whole first row reads as one
  /// control instead of three stacked bands eating the top of the screen.
  final Widget dateSelector;

  @override
  State<ReportFilterBar> createState() => _ReportFilterBarState();
}

class _ReportFilterBarState extends State<ReportFilterBar> {
  /// Owned here, and only here.
  ///
  /// Built inline in `build` at first, which meant a fresh controller on every
  /// keystroke — each character re-ran the parent's setState, rebuilt this
  /// widget, and handed the field a brand-new controller. The field loses
  /// focus after the first letter that way, and every discarded controller
  /// leaks.
  late final TextEditingController _searchController = TextEditingController(
    text: widget.filters.search,
  );

  /// Below this the row would squeeze the search box to nothing, so the
  /// controls wrap onto as many lines as they need instead.
  static const double _anchoParaUnaFila = 1150;

  static const double _anchoFecha = 236;
  static const double _anchoFiltro = 170;

  @override
  void didUpdateWidget(ReportFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the search was changed from outside — "Limpiar" — does the box
    // need correcting. Writing on every rebuild would fight the cursor.
    if (widget.filters.search != _searchController.text) {
      _searchController.text = widget.filters.search;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ReportFilters get filters => widget.filters;
  ValueChanged<ReportFilters> get onChanged => widget.onChanged;
  CatalogProvider get catalog => widget.catalog;

  /// The ids present in the loaded tasks for one field, with [kSinAsignar]
  /// standing in for the ones that have none, sorted by the name shown.
  List<String> _options(
    String? Function(TaskModel) idOf,
    String Function(String?) nameOf,
  ) {
    final ids = <String>{for (final t in widget.tasks) idOf(t) ?? kSinAsignar};
    String display(String id) => nameOf(id == kSinAsignar ? null : id);
    return ids.toList()..sort(
      (a, b) => display(a).toLowerCase().compareTo(display(b).toLowerCase()),
    );
  }

  Widget _buscador(AppColorsExtension colors) {
    return TextField(
      controller: _searchController,
      onChanged: (v) => onChanged(filters.copyWith(search: v)),
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        hintText: 'Buscar por cliente o teléfono',
        hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
        prefixIcon: Icon(
          LucideIcons.search,
          size: 18,
          color: colors.textSecondary,
        ),
        suffixIcon: filters.search.isEmpty
            ? null
            : IconButton(
                tooltip: 'Borrar búsqueda',
                icon: Icon(
                  LucideIcons.x,
                  size: 16,
                  color: colors.textSecondary,
                ),
                onPressed: () => onChanged(filters.copyWith(search: '')),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
      ),
    );
  }

  List<Widget> _filtros() {
    return [
      _FilterDropdown(
        label: 'Equipo',
        value: filters.groupId,
        options: _options((t) => t.groupId, catalog.groupName),
        nameOf: catalog.groupName,
        onChanged: (v) => onChanged(
          v == null
              ? filters.copyWith(clearGroup: true)
              : filters.copyWith(groupId: v),
        ),
      ),
      _FilterDropdown(
        label: 'Encargado',
        value: filters.userId,
        options: _options((t) => t.assignedUserId, catalog.userName),
        nameOf: catalog.userName,
        onChanged: (v) => onChanged(
          v == null
              ? filters.copyWith(clearUser: true)
              : filters.copyWith(userId: v),
        ),
      ),
      _FilterDropdown(
        label: 'Estado',
        value: filters.statusId,
        options: _options((t) => t.statusId, catalog.statusName),
        nameOf: catalog.statusName,
        onChanged: (v) => onChanged(
          v == null
              ? filters.copyWith(clearStatus: true)
              : filters.copyWith(statusId: v),
        ),
      ),
      _FilterDropdown(
        label: 'Tipo',
        value: filters.taskTypeId,
        options: _options((t) => t.taskTypeId, catalog.taskTypeName),
        nameOf: catalog.taskTypeName,
        onChanged: (v) => onChanged(
          v == null
              ? filters.copyWith(clearTaskType: true)
              : filters.copyWith(taskTypeId: v),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final filtros = [
      for (final f in _filtros()) SizedBox(width: _anchoFiltro, child: f),
    ];
    final limpiar = TextButton.icon(
      onPressed: () => onChanged(const ReportFilters()),
      icon: const Icon(LucideIcons.x, size: 15),
      label: const Text('Limpiar'),
      style: TextButton.styleFrom(foregroundColor: colors.error),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _anchoParaUnaFila) {
              return Row(
                children: [
                  SizedBox(width: _anchoFecha, child: widget.dateSelector),
                  const SizedBox(width: AppSpacing.sm),
                  // Takes whatever the fixed controls leave, so the row fills
                  // the width instead of trailing off into empty space.
                  Expanded(child: _buscador(colors)),
                  for (final f in filtros) ...[
                    const SizedBox(width: AppSpacing.sm),
                    f,
                  ],
                  if (!filters.isEmpty) ...[
                    const SizedBox(width: AppSpacing.xs),
                    limpiar,
                  ],
                ],
              );
            }
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: _anchoFecha, child: widget.dateSelector),
                SizedBox(width: 260, child: _buscador(colors)),
                ...filtros,
                if (!filters.isEmpty) limpiar,
              ],
            );
          },
        ),
        // Shown only while something is filtered, and deliberately loud about
        // it: every number below and every export now describes a subset, and
        // a filtered total screenshotted as "the month" is a mistake nothing
        // else on screen would catch.
        if (!filters.isEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.filter, size: 14, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Filtrado: mostrando ${widget.matchCount} de '
                    '${widget.tasks.length} tareas. Los indicadores y las '
                    'exportaciones usan lo filtrado.',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.nameOf,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final String Function(String?) nameOf;
  final ValueChanged<String?> onChanged;

  String _display(String id) => id == kSinAsignar ? nameOf(null) : nameOf(id);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = value != null;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: active ? colors.primary.withValues(alpha: 0.10) : colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: active ? colors.primary : colors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isDense: true,
          isExpanded: true,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          dropdownColor: colors.surface,
          style: TextStyle(color: colors.textPrimary, fontSize: 13),
          // Closed, all four of these read "Todos" and nothing else, so they
          // sat in a row as four identical boxes with no way to tell which was
          // which. The label was passed as `hint`, which only shows when
          // nothing is selected — and "Todos" *is* a selection, so it never
          // appeared. The menu keeps the bare option names; only the button
          // carries the field it belongs to.
          selectedItemBuilder: (context) => [
            _Closed(label: label, value: 'Todos', muted: true),
            for (final id in options)
              _Closed(label: label, value: _display(id)),
          ],
          items: [
            DropdownMenuItem<String?>(
              child: Text(
                'Todos',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
            ),
            for (final id in options)
              DropdownMenuItem<String?>(
                value: id,
                child: Text(
                  _display(id),
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// What a dropdown shows while closed: the field it filters, then what it is
/// currently set to.
class _Closed extends StatelessWidget {
  const _Closed({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;

  /// True while the filter is off, so "Todos" reads as the resting state
  /// rather than as a choice somebody made.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                color: muted ? colors.textSecondary : colors.textPrimary,
                fontSize: 13,
                fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
