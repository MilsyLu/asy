import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/support_case_metrics.dart';
import '../../models/support_case_model.dart';
import '../../widgets/kpi_icon_card.dart';

/// El Resumen: la tercera forma de mirar los mismos casos, junto a Tabla y
/// Kanban.
///
/// La tira de indicadores de arriba responde "¿cuántos hay?". Esta pantalla
/// responde lo que esa tira no puede: si el trabajo se está acumulando y cuánto
/// se tarda en sacarlo.
///
/// Muestra los casos que ya pasaron los filtros de la pantalla — buscador,
/// etiqueta, filtro rápido. Es lo mismo que ven la tabla y el tablero, así que
/// cambiar un filtro cambia las tres vistas igual, sin un segundo juego de
/// reglas que pueda contradecir al primero.
class SupportCasesSummary extends StatelessWidget {
  const SupportCasesSummary({super.key, required this.cases});

  final List<SupportCaseModel> cases;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resueltos = cases.where((c) => c.resolvedAt != null).length;
    final promedio = averageResolutionTime(cases);
    final masViejo = oldestOpenDays(cases);
    final semanas = weeklyFlow(cases, now: DateTime.now());

    final tarjetas = <Widget>[
      KpiIconCard(
        icon: LucideIcons.timer,
        label: 'Tiempo medio de resolución',
        // Guion y no "0": sin casos resueltos no hay promedio que mostrar, y
        // un cero se leería como "se resuelven al instante".
        value: promedio == null ? '—' : formatResolutionTime(promedio),
        color: colors.primary,
      ),
      KpiIconCard(
        icon: LucideIcons.checkCircle2,
        label: 'Casos resueltos',
        value: '$resueltos',
        color: Colors.green,
      ),
      KpiIconCard(
        icon: LucideIcons.percent,
        label: 'Tasa de resolución',
        value: cases.isEmpty
            ? '—'
            : '${(resueltos * 100 / cases.length).round()} %',
        color: Colors.blue,
      ),
      KpiIconCard(
        icon: LucideIcons.hourglass,
        label: 'Caso abierto más viejo',
        value: masViejo == null ? '—' : '$masViejo días',
        color: masViejo != null && masViejo > 10 ? Colors.red : Colors.orange,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Tarjetas(children: tarjetas),
          const SizedBox(height: 20),
          _GraficaFlujo(semanas: semanas),
        ],
      ),
    );
  }
}

/// Las cuatro tarjetas: repartidas en una fila cuando hay ancho, deslizables
/// cuando no.
class _Tarjetas extends StatelessWidget {
  const _Tarjetas({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Por debajo de esto, cuatro tarjetas con etiquetas largas
        // ("Tiempo medio de resolución") dejan de caber sin recortarse hasta
        // ser ilegibles. Ahí se deslizan de lado, que es lo que hace el resto
        // de la pantalla en un teléfono.
        if (constraints.maxWidth < 620) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  SizedBox(width: 190, child: children[i]),
                ],
              ],
            ),
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
}

/// Entradas contra salidas por semana.
///
/// La única gráfica de la versión chica, y a propósito: es la que responde la
/// pregunta que ningún indicador suelto responde — si el trabajo entra más
/// rápido de lo que sale, el montón crece aunque todos los números del día se
/// vean bien.
class _GraficaFlujo extends StatelessWidget {
  const _GraficaFlujo({required this.semanas});

  final List<SupportWeek> semanas;

  static const _meses = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  String _etiqueta(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entradas = Colors.orange;
    final salidas = Colors.green;

    final maximo = semanas
        .expand((w) => [w.opened, w.resolved])
        .fold<int>(0, (a, b) => a > b ? a : b);
    // Con todo en cero el gráfico no tiene alto que repartir y fl_chart dibuja
    // una rejilla degenerada. Un techo mínimo lo mantiene legible y vacío, que
    // es la lectura correcta cuando de verdad no pasó nada.
    final techo = (maximo == 0 ? 4 : maximo + 1).toDouble();

    final totalEntradas = semanas.fold<int>(0, (a, w) => a + w.opened);
    final totalSalidas = semanas.fold<int>(0, (a, w) => a + w.resolved);
    final gana = totalSalidas >= totalEntradas;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // El título es la pregunta que el gráfico contesta. La gráfica de
          // tendencia del Dashboard se titulaba con el nombre del dato y hubo
          // que explicarla; una pregunta se lee sola.
          Text(
            '¿Resolvemos más de lo que entra?',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Últimas ${semanas.length} semanas · '
            '$totalEntradas entraron, $totalSalidas se resolvieron',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                gana ? LucideIcons.trendingDown : LucideIcons.trendingUp,
                size: 14,
                color: gana ? salidas : entradas,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  gana
                      ? 'El montón de casos abiertos no está creciendo.'
                      : 'Entran más de los que se resuelven: el montón crece.',
                  style: TextStyle(
                    color: gana ? salidas : entradas,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Leyenda(color: entradas, texto: 'Entraron'),
              const SizedBox(width: 16),
              _Leyenda(color: salidas, texto: 'Se resolvieron'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: context.isMobile ? 200 : 260,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: techo,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: techo <= 5 ? 1 : (techo / 4).ceilToDouble(),
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: colors.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: techo <= 5 ? 1 : (techo / 4).ceilToDouble(),
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: 1,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= semanas.length) {
                          return const SizedBox.shrink();
                        }
                        // En pantalla angosta ocho etiquetas se pisan unas a
                        // otras: se deja una de cada dos, y siempre la última,
                        // que es la semana en curso.
                        final salta = context.isMobile && semanas.length > 4;
                        if (salta && i.isOdd && i != semanas.length - 1) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _etiqueta(semanas[i].start),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => [
                      for (final s in spots)
                        LineTooltipItem(
                          '${s.barIndex == 0 ? 'Entraron' : 'Se resolvieron'}: '
                          '${s.y.toInt()}',
                          TextStyle(
                            color: s.barIndex == 0 ? entradas : salidas,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  _linea(
                    [
                      for (var i = 0; i < semanas.length; i++)
                        FlSpot(i.toDouble(), semanas[i].opened.toDouble()),
                    ],
                    entradas,
                  ),
                  _linea(
                    [
                      for (var i = 0; i < semanas.length; i++)
                        FlSpot(i.toDouble(), semanas[i].resolved.toDouble()),
                    ],
                    salidas,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Segmentos rectos, no curva: son casos contados por semana. Una curva pasa
  /// por valores que ninguna semana tuvo y se sale por debajo de cero entre dos
  /// semanas flojas — dibuja un dato que no existe.
  LineChartBarData _linea(List<FlSpot> spots, Color color) => LineChartBarData(
    spots: spots,
    isCurved: false,
    color: color,
    barWidth: 2.5,
    dotData: FlDotData(
      show: true,
      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
        radius: 3,
        color: color,
        strokeWidth: 0,
        strokeColor: color,
      ),
    ),
    belowBarData: BarAreaData(
      show: true,
      color: color.withValues(alpha: 0.08),
    ),
  );
}

class _Leyenda extends StatelessWidget {
  const _Leyenda({required this.color, required this.texto});

  final Color color;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          texto,
          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
