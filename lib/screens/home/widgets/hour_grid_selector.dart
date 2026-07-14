import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive/app_spacing.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../models/task_model.dart';
import '../../../services/task_repository.dart';

const Color _kOrangeBusy = Color(0xFFFF9800);

/// Responsive grid of hour cards with real-time occupancy data.
///
/// Replaces the dropdown in [AddEditTaskPage] when the global config is
/// "Usar horarios configurados" (catalog mode). Each card shows how many tasks
/// are already scheduled at that hour on [selectedDate] and is color-coded:
///  - 0 tasks → green  ("Libre")
///  - 1 task  → amber  ("1 tarea")
///  - 2+ tasks → orange ("N tareas")
///
/// The selected card is highlighted with the primary accent color + a checkmark.
/// The occupancy stream refreshes automatically when [selectedDate] changes.
class HourGridSelector extends StatefulWidget {
  const HourGridSelector({
    super.key,
    required this.hours,
    required this.selectedDate,
    required this.selectedHour,
    required this.onHourSelected,
  });

  /// Catalog hour strings in "HH:MM" 24-hour format.
  final List<String> hours;
  final DateTime selectedDate;
  final String? selectedHour;
  final ValueChanged<String> onHourSelected;

  @override
  State<HourGridSelector> createState() => _HourGridSelectorState();
}

class _HourGridSelectorState extends State<HourGridSelector> {
  late Stream<List<TaskModel>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = context.read<TaskRepository>().watchTasksForDate(widget.selectedDate);
  }

  @override
  void didUpdateWidget(HourGridSelector old) {
    super.didUpdateWidget(old);
    if (!_sameDay(old.selectedDate, widget.selectedDate)) {
      setState(() {
        _stream = context.read<TaskRepository>().watchTasksForDate(widget.selectedDate);
      });
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // "HH:MM" → "h:MM AM/PM"
  static String _fmtHour(String h) {
    final parts = h.split(':');
    if (parts.length != 2) return h;
    final hr = int.tryParse(parts[0]);
    final mn = int.tryParse(parts[1]);
    if (hr == null || mn == null) return h;
    final pm = hr >= 12;
    final dh = hr == 0 ? 12 : (hr > 12 ? hr - 12 : hr);
    return '$dh:${mn.toString().padLeft(2, '0')} ${pm ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final w = MediaQuery.sizeOf(context).width;
    final cols = w < 360
        ? 1
        : w < Breakpoints.mobile
            ? 2
            : w < Breakpoints.tablet
                ? 3
                : 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecciona una hora',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'La disponibilidad se actualiza automáticamente según la fecha elegida.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.md),
        StreamBuilder<List<TaskModel>>(
          stream: _stream,
          builder: (ctx, snap) {
            final tasks = snap.data ?? [];
            final counts = <String, int>{};
            for (final t in tasks) {
              counts[t.hour] = (counts[t.hour] ?? 0) + 1;
            }

            final freeCount =
                widget.hours.where((h) => (counts[h] ?? 0) == 0).length;
            final lowCount =
                widget.hours.where((h) => (counts[h] ?? 0) == 1).length;
            final busyCount =
                widget.hours.where((h) => (counts[h] ?? 0) >= 2).length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryCard(free: freeCount, low: lowCount, busy: busyCount),
                const SizedBox(height: AppSpacing.md),
                if (widget.hours.isEmpty)
                  Text(
                    'No hay horarios configurados en el catálogo. '
                    'Agrégalos desde el panel de administración.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 2.2,
                    ),
                    itemCount: widget.hours.length,
                    itemBuilder: (_, i) {
                      final h = widget.hours[i];
                      return _HourCard(
                        label: _fmtHour(h),
                        rawHour: h,
                        count: counts[h] ?? 0,
                        isSelected: h == widget.selectedHour,
                        onTap: () => widget.onHourSelected(h),
                      );
                    },
                  ),
                if (widget.selectedHour == null && widget.hours.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Selecciona una hora',
                    style: TextStyle(color: colors.error, fontSize: 12),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

// ─── Summary card ────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.free, required this.low, required this.busy});

  final int free;
  final int low;
  final int busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.calendarDays, color: colors.primary, size: 14),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Disponibilidad',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: 4,
            children: [
              _SummaryChip(emoji: '🟢', label: 'Libres', count: free),
              _SummaryChip(emoji: '🟡', label: 'Ocupadas', count: low),
              _SummaryChip(emoji: '🟠', label: 'Muy ocupadas', count: busy),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.emoji,
    required this.label,
    required this.count,
  });

  final String emoji;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(
          '$label: $count',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ─── Hour card ───────────────────────────────────────────────────────────────

class _HourCard extends StatefulWidget {
  const _HourCard({
    required this.label,
    required this.rawHour,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;     // formatted display "h:MM AM/PM"
  final String rawHour;   // "HH:MM" — used for semantics
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_HourCard> createState() => _HourCardState();
}

class _HourCardState extends State<_HourCard> {
  bool _hovered = false;

  Color _statusColor(AppColorsExtension colors) {
    if (widget.isSelected) return colors.primary;
    if (widget.count == 0) return colors.success;
    if (widget.count == 1) return colors.statusPending;
    return _kOrangeBusy;
  }

  String _statusLabel() {
    if (widget.count == 0) return 'Libre';
    if (widget.count == 1) return '1 tarea';
    return '${widget.count} tareas';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sc = _statusColor(colors);
    final sel = widget.isSelected;

    final bgColor = sel
        ? colors.primary.withValues(alpha: 0.12)
        : sc.withValues(alpha: _hovered ? 0.12 : 0.07);

    final borderColor = sel
        ? colors.primary
        : (_hovered ? sc.withValues(alpha: 0.7) : sc.withValues(alpha: 0.3));

    return Semantics(
      button: true,
      selected: sel,
      label: '${widget.label}, ${_statusLabel()}${sel ? ', seleccionado' : ''}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: borderColor, width: sel ? 2.0 : 1.0),
            boxShadow: [
              BoxShadow(
                color: sc.withValues(
                    alpha: sel ? 0.18 : (_hovered ? 0.12 : 0.05)),
                blurRadius: sel ? 8 : (_hovered ? 5 : 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              splashColor: sc.withValues(alpha: 0.18),
              focusColor: sc.withValues(alpha: 0.14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Stack(
                  children: [
                    if (sel)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Icon(
                          LucideIcons.checkCircle2,
                          size: 14,
                          color: colors.primary,
                        ),
                      ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: sel ? colors.primary : colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: sc,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _statusLabel(),
                                style: TextStyle(
                                  color: sc,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
