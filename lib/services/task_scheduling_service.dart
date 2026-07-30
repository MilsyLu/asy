import 'package:flutter/material.dart';

import '../providers/catalog_provider.dart';

/// Centralizes time-selection logic for task creation and editing.
///
/// Sprint 22: mode detection and time formatting helpers.
/// Next sprint: drives visual representation without changing this logic —
/// only [catalogHours] / [formatTimeOfDay] / [parseHourString] need to be
/// consumed by the new widgets, not duplicated in each one.
///
/// Time-selection *mode* (free vs. catalog) is no longer read here — it's
/// per-team (`GroupModel.timeSelectionMode`/`useFreePicker`), read directly
/// via `CatalogProvider.groupById(groupId)` at each call site, since the
/// relevant group isn't known inside this stateless helper.
class TaskSchedulingService {
  TaskSchedulingService._();

  /// Returns the hour strings from the catalog, used in catalog mode.
  static List<String> catalogHours(CatalogProvider catalog) =>
      catalog.availableHours.map((h) => h.hour).toList();

  /// Formats [TimeOfDay] as the "HH:MM" string stored in Firestore.
  static String formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Parses a "HH:MM" Firestore string back to [TimeOfDay].
  static TimeOfDay parseHourString(String hourStr) {
    final parts = hourStr.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null) return TimeOfDay(hour: h, minute: m);
    }
    return TimeOfDay.now();
  }
}
