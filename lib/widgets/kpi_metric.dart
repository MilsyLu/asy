import 'package:flutter/material.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';

/// Un indicador: icono en un cuadro redondeado, nombre y cifra, centrados.
///
/// Es el bloque del Dashboard, sacado aquí para que Reportes muestre los
/// suyos igual. Había dos formas distintas de dibujar lo mismo en la app —el
/// Dashboard con icono y la cifra grande centrada, Reportes con el nombre
/// arriba a la izquierda y el número de color— y bastaba poner las dos
/// pantallas lado a lado para que se notara.
///
/// No trae tarjeta propia a propósito: quien lo usa decide si van varios
/// dentro de un mismo recuadro separados por líneas —como en el Dashboard— o
/// cada uno en el suyo.
class KpiMetric extends StatelessWidget {
  const KpiMetric({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.accentColor,
    this.linkLabel,
    this.onTap,
    this.dense = false,
  });

  final IconData icon;
  final String title;

  /// Texto y no número: hay indicadores que son porcentajes ("63 %").
  final String value;

  final Color? accentColor;
  final String? linkLabel;
  final VoidCallback? onTap;

  /// Versión baja, para una fila que comparte pantalla con otras cosas.
  ///
  /// El icono se pone al lado del nombre en vez de encima. La cifra mide 16
  /// en los dos modos: Michel la pidió así en Reportes y después en el
  /// Dashboard, y un número gigante no era información, era sólo alto.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = accentColor ?? colors.primary;
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        // Sin esto los toques caen sólo sobre las letras y el icono, no en
        // los huecos entre ellos — que en un bloque tan aireado es casi todo.
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dense)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: accent, size: 14),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppSpacing.xs),
                ),
                child: Icon(icon, color: accent, size: 14),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                height: 1.05,
              ),
            ),
            if (linkLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                linkLabel!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
