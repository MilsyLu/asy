import 'package:flutter/material.dart';

import '../providers/catalog_provider.dart';
import '../providers/system_config_provider.dart';

/// Centralizes time-selection logic for task creation and editing.
///
/// Sprint 22: mode detection and time formatting helpers.
/// Next sprint: drives visual representation without changing this logic —
/// only [catalogHours] / [formatTimeOfDay] / [parseHourString] need to be
/// consumed by the new widgets, not duplicated in each one.
class TaskSchedulingService {
  TaskSchedulingService._();

  /// Whether the current global config uses the free TimePicker instead of
  /// the catalog dropdown.
  static bool useFreePicker(SystemConfigProvider config) =>
      config.config.useFreePicker;

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
