import 'package:flutter/material.dart';

import '../core/utils/date_utils.dart';

/// The period the Dashboard is showing.
///
/// Lives outside the page because two widgets need it now: the Dashboard runs
/// its query from it, and the shell's top bar draws the selector. Michel asked
/// for that selector to sit up in the bar, and the pages hang inside an
/// `IndexedStack` — every one of them builds, whether visible or not — so
/// having a page push widgets upward would mean several pages writing over
/// each other. Shared state read by both is the version that cannot go wrong.
///
/// The ranges themselves used to be labels and nothing more: picking one
/// changed the text and left every number exactly as it was, because the query
/// was hard-wired to 30 days. That is worse than a disabled control — the
/// screen claimed to show the year while showing the month, with no way to
/// tell from looking.
class DashboardRangeController extends ChangeNotifier {
  DashboardRangeController() {
    select(defaultIndex);
  }

  static const List<String> labels = [
    'Últimos 7 días',
    'Últimos 30 días',
    'Este mes',
    'Este año',
    'Personalizado',
  ];

  static const int defaultIndex = 1; // "Últimos 30 días"
  static const int customIndex = 4;

  int _index = defaultIndex;
  late DateTime _start;
  late DateTime _end;

  int get index => _index;
  DateTime get start => _start;
  DateTime get end => _end;

  /// One extra day so "Próximas 24 horas" sees tomorrow without a second
  /// stream. On a custom range that ends in the past there is nothing ahead to
  /// show, which is the honest answer for a window that already closed.
  DateTime get queryEnd => _end.add(const Duration(days: 1));

  /// What the selector and the empty state call the current period.
  String get label => _index == customIndex
      ? '${AppDateUtils.formatShortDate(_start)} — ${AppDateUtils.formatShortDate(_end)}'
      : labels[_index];

  /// First and last day covered by [index], both inclusive.
  static ({DateTime start, DateTime end}) rangeFor(int index, DateTime today) {
    switch (index) {
      case 0:
        return (start: today.subtract(const Duration(days: 7)), end: today);
      case 2:
        return (start: DateTime(today.year, today.month, 1), end: today);
      case 3:
        return (start: DateTime(today.year, 1, 1), end: today);
      default:
        return (start: today.subtract(const Duration(days: 30)), end: today);
    }
  }

  /// Points the screen at a new period. Everything downstream reads [start]
  /// and [end], so this is the whole change.
  void select(int index, {DateTimeRange? custom}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (custom != null) {
      _start = DateTime(custom.start.year, custom.start.month, custom.start.day);
      _end = DateTime(custom.end.year, custom.end.month, custom.end.day);
    } else {
      final range = rangeFor(index, today);
      _start = range.start;
      _end = range.end;
    }

    _index = index;
    notifyListeners();
  }
}
