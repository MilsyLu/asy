import 'package:flutter/material.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';

/// El detalle, flotando sobre la lista, cuando no hay ancho para el panel.
///
/// Casos de Soporte y Requerimientos muestran el detalle en una columna a la
/// derecha, pero sólo a partir de cierto ancho. Por debajo, el clic abría un
/// panel que nadie dibujaba: no pasaba absolutamente nada. Michel lo encontró
/// con la ventana a media pantalla.
///
/// Se dibuja dentro del árbol, en un [Stack] sobre la lista, y no con
/// `showDialog`: así aparece y desaparece siguiendo el mismo estado que el
/// panel lateral —uno solo decide si hay detalle abierto— y al estirar la
/// ventana se convierte en la columna de la derecha sola, sin quedar una
/// ventana colgada encima.
///
/// El fondo se oscurece sin desenfoque, como el resto de la app.
class VentanaFlotante extends StatelessWidget {
  const VentanaFlotante({
    super.key,
    required this.child,
    required this.onClose,
    this.ancho = 560,
  });

  final Widget child;
  final VoidCallback onClose;
  final double ancho;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pantalla = MediaQuery.sizeOf(context);

    return Positioned.fill(
      child: Stack(
        children: [
          // Tocar fuera cierra, como en cualquier ventana de la app.
          GestureDetector(
            onTap: onClose,
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: ancho,
                  // Alto acotado: un caso con veinte entradas de seguimiento
                  // crecería hasta salirse por arriba y por abajo.
                  maxHeight: pantalla.height * 0.88,
                ),
                child: Material(
                  color: colors.surface,
                  elevation: 8,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
