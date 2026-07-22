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

/// The inverse of [parseHexColor] — serializes a [Color] (e.g. picked via
/// `flutter_colorpicker`) back to the "#RRGGBB" format stored on
/// [TaskTypeModel.color]. Uses the 0.0–1.0 component getters rather than the
/// deprecated 0–255 `.value` accessor.
///
/// Named `taskTypeColorToHex` (not `colorToHex`) because `flutter_colorpicker`
/// itself exports a top-level `colorToHex`, which would otherwise collide.
String taskTypeColorToHex(Color color) {
  String channel(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${channel(color.r)}${channel(color.g)}${channel(color.b)}'.toUpperCase();
}

/// Centralizes resolving a [TaskTypeModel]'s configured color (Sprint 5.5),
/// previously duplicated as ad-hoc hex parsing in individual screens.
extension TaskTypeColor on TaskTypeModel {
  /// The type's configured color, or null if unset/invalid. Every call site
  /// falls back to the active theme accent (`colors.primary`) when this is
  /// null, so legacy types without a color keep looking exactly as before.
  Color? get parsedColor => parseHexColor(color);
}
