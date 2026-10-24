import 'package:flutter/material.dart';

import '../core/theme/theme_colors.dart';

/// Las tarjetas de un tablero repartidas en rejilla, cuando el tablero dejó
/// de ser un tablero.
///
/// Con un filtro puesto lo normal es que sólo una columna tenga tarjetas: el
/// resto quedan vacías al lado y lo que uno vino a ver se apretuja en una
/// tira de 260 px mientras sobra media pantalla. Ahí no hay flujo que mirar
/// —ya se eligió el estado— así que las tarjetas se reparten a todo el ancho.
///
/// Vive aquí y no dentro de un tablero porque es la misma decisión en los
/// dos: Requerimientos y Casos de Soporte. Lo que no se comparte son las
/// tarjetas ni el arrastrar y soltar, que sólo tiene el de casos.
class SingleColumnGrid extends StatelessWidget {
  const SingleColumnGrid({
    super.key,
    required this.titulo,
    required this.color,
    required this.cantidad,
    required this.itemBuilder,
    this.altoTarjeta = 150,
    this.anchoMaximo = 340,
  });

  /// Nombre de la única columna con contenido, para que no se pierda de vista
  /// qué se está mirando al desaparecer el resto.
  final String titulo;
  final Color color;
  final int cantidad;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// Alto fijo de cada tarjeta. Una rejilla necesita saberlo de antemano, y
  /// las tarjetas de los dos tableros ya recortan su texto a dos líneas.
  final double altoTarjeta;

  final double anchoMaximo;

  /// Cuántas de [conteos] tienen algo. Quien dibuja el tablero decide con
  /// esto si usa la rejilla.
  static int columnasConContenido(Iterable<int> conteos) =>
      conteos.where((n) => n > 0).length;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                '$titulo · $cantidad',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: anchoMaximo,
                mainAxisExtent: altoTarjeta,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: cantidad,
              itemBuilder: itemBuilder,
            ),
          ),
        ],
      ),
    );
  }
}
