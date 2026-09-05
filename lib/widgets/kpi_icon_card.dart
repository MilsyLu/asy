import 'package:flutter/material.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';

/// Tarjeta de indicador con icono en círculo, cifra grande y etiqueta.
///
/// Vivía privada dentro de `support_cases_page.dart`, y el Resumen de casos
/// necesitaba exactamente la misma. Copiarla habría sido la tercera vez en este
/// proyecto que algo existe por duplicado y una de las copias se queda vieja
/// —ya pasó con los recordatorios de casos y con el enlace de clientes—, así
/// que se sacó aquí y ahora hay una sola.
///
/// No se reutilizó [KpiCard] de `kpi_card.dart` porque es otro diseño: sin
/// icono y con la cifra de color. Las dos conviven hoy en la app, y unificarlas
/// cambiaría el aspecto de Reportes y del Dashboard — que es una decisión
/// aparte, no un efecto secundario de esta pantalla.
///
/// [value] es texto y no un número: los indicadores del Resumen no son cuentas
/// sino "1,4 días" o "54 %". Quien tenga una cuenta escribe `'$n'`.
class KpiIconCard extends StatelessWidget {
  const KpiIconCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.width = 148,
    this.labelAbove = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  /// Ancho natural. Dentro de un `Expanded` no se aplica: manda el padre.
  final double width;

  /// Saca el nombre fuera de la tarjeta, encima y en letra chica.
  ///
  /// Dentro, el nombre comparte el ancho con el círculo del icono y la cifra,
  /// y en una tira de cinco tarjetas se quedaba en "Caso…", "Urge…", "Más d…":
  /// cinco tarjetas que no dicen de qué son. Afuera dispone del ancho entero.
  final bool labelAbove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (labelAbove) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _tarjeta(context, conNombre: false),
        ],
      );
    }
    return _tarjeta(context, conNombre: true);
  }

  Widget _tarjeta(BuildContext context, {required bool conNombre}) {
    final colors = context.colors;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (conNombre)
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
