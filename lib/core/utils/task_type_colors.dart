import 'package:flutter/material.dart';

import '../../models/task_type_model.dart';

/// Parses a "#RRGGBB" hex string into a [Color]. Returns null for
/// null/empty/malformed input.
Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final cleaned = hex.replaceFirst('#', '');
  final value = int.tryParse('FF$cleaned', radix: 16);
  return value != null ? Color(value) : null;
}

/// Centralizes resolving a [TaskTypeModel]'s configured color (Sprint 5.5),
/// previously duplicated as ad-hoc hex parsing in individual screens.
extension TaskTypeColor on TaskTypeModel {
  /// The type's configured color, or null if unset/invalid. Every call site
  /// falls back to the active theme accent (`colors.primary`) when this is
  /// null, so legacy types without a color keep looking exactly as before.
  Color? get parsedColor => parseHexColor(color);
}
