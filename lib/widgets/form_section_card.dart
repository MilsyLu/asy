import 'package:flutter/material.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';

/// Shared "sección" container for form-like tablet/desktop layouts — icon +
/// title (+ optional trailing actions) header over a bordered surface. Same
/// visual language as the admin row cards (Equipos/Estados/Tipos de tarea)
/// and Configuración's preference cards.
class FormSectionCard extends StatelessWidget {
  const FormSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;

  /// Optional header actions (e.g. "Limpiar"/"Crear tarea" in the inline
  /// task-creation panel) shown at the right of the title row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      // Arriba menos aire que a los lados: el titulo ya se separa solo por
      // su propio alto, y 16 px encima de "Nueva tarea" empujaban el
      // formulario entero hacia abajo.
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 10, AppSpacing.md, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.primary, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
