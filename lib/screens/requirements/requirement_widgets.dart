import 'package:flutter/material.dart';

import '../../core/constants/requirement_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';

/// Insignia de estado, tipo o prioridad de un requerimiento.
///
/// Una sola para las tres cosas: son la misma forma —texto corto sobre un
/// fondo del color del valor— y tenerlas separadas sólo garantizaba que se
/// fueran pareciendo cada vez menos entre sí.
class RequirementBadge extends StatelessWidget {
  const RequirementBadge({
    super.key,
    required this.label,
    required this.color,
    this.dense = false,
  });

  factory RequirementBadge.estado(String status, {bool dense = false}) =>
      RequirementBadge(
        label: status,
        color: RequirementStatus.colorFor(status),
        dense: dense,
      );

  factory RequirementBadge.tipo(String type, {bool dense = false}) =>
      RequirementBadge(
        label: type,
        color: RequirementType.colorFor(type),
        dense: dense,
      );

  factory RequirementBadge.prioridad(String p, {bool dense = false}) =>
      RequirementBadge(
        label: p,
        color: RequirementPriority.colorFor(p),
        dense: dense,
      );

  final String label;
  final Color color;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// El módulo de VinApp al que afecta el requerimiento.
///
/// Sin color propio a propósito: ya hay tres insignias de color en cada fila
/// —estado, tipo y prioridad— y una cuarta compite con las que de verdad hay
/// que mirar de un vistazo.
class RequirementModuleChip extends StatelessWidget {
  const RequirementModuleChip({super.key, required this.module});

  final String module;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: colors.divider),
      ),
      child: Text(
        module,
        style: TextStyle(color: colors.textSecondary, fontSize: 11),
      ),
    );
  }
}
