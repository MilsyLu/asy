import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/support_case_metrics.dart';
import '../../models/support_case_model.dart';
import '../../widgets/calendario_menu.dart';
import '../../widgets/kpi_icon_card.dart';

/// El periodo que muestra el Resumen.
///
/// Vive en el estado de la página y no aquí dentro para que sobreviva a
/// cambiar de vista: elegir "Últimos 7 días", irse a la Tabla y volver no
/// debería devolverlo al valor por defecto.
///
/// No reutiliza `DashboardRangeController` a propósito: ese es uno solo para
/// toda la app, así que cambiar el periodo aquí también le cambiaría el suyo
/// al Dashboard, sin que nada en pantalla lo anuncie.
class PeriodoResumen {
  const PeriodoResumen({
    required this.inicio,
    required this.fin,
    required this.indice,
    this.etiquetaPropia,
  });

  /// Primer día del periodo, incluido.
  final DateTime inicio;

  /// Último día del periodo, incluido.
  final DateTime fin;

  /// Cuál de [etiquetas] está elegida.
  final int indice;

  /// Sólo para un periodo personalizado: las dos fechas elegidas.
  final String? etiquetaPropia;

  static const List<String> etiquetas = [
    'Últimos 7 días',
    'Últimos 30 días',
    'Este mes',
    'Personalizado',
  ];

  static const int indicePersonalizado = 3;
  static const int indicePorDefecto = 1;

  String get etiqueta => etiquetaPropia ?? etiquetas[indice];

  /// Cuántos días abarca, ambos extremos incluidos.
  int get dias => dayOnly(fin).difference(dayOnly(inicio)).inDays + 1;

  factory PeriodoResumen.preset(int indice, {DateTime? hoy}) {
    final ahora = dayOnly(hoy ?? DateTime.now());
    switch (indice) {
      case 0:
        return PeriodoResumen(
          inicio: DateTime(ahora.year, ahora.month, ahora.day - 6),
          fin: ahora,
          indice: 0,
        );
      case 2:
        return PeriodoResumen(
          inicio: DateTime(ahora.year, ahora.month, 1),
          fin: ahora,
          indice: 2,
        );
      default:
        return PeriodoResumen(
          inicio: DateTime(ahora.year, ahora.month, ahora.day - 29),
          fin: ahora,
          indice: 1,
        );
    }
  }

  factory PeriodoResumen.personalizado(DateTimeRange r) => PeriodoResumen(
    inicio: dayOnly(r.start),
    fin: dayOnly(r.end),
    indice: indicePersonalizado,
    etiquetaPropia: '${formatDay(r.start)} – ${formatDay(r.end)}',
  );
}

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
/// reglas que pueda contradecir al primero. El periodo es lo único que sólo
/// aplica aquí.
class SupportCasesSummary extends StatelessWidget {
  const SupportCasesSummary({
    super.key,
    required this.cases,
    required this.periodo,
    required this.onPeriodoChanged,
  });

  final List<SupportCaseModel> cases;
  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onPeriodoChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final reportados = reportedIn(cases, periodo.inicio, periodo.fin);
    final resueltos = resolvedIn(cases, periodo.inicio, periodo.fin);
    final promedio = averageResolutionTime(resueltos);
    // A diferencia de los otros tres, éste NO mira el periodo: es un hecho de
    // ahora mismo. Acotarlo escondería el caso de 41 días en cuanto se
    // eligieran los últimos 7, que es justo cuando más falta hace verlo.
    final masViejo = oldestOpenDays(cases);
    final dias = dailyFlow(cases, start: periodo.inicio, end: periodo.fin);

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
        label: 'Resueltos en el periodo',
        value: '${resueltos.length}',
        color: Colors.green,
      ),
      KpiIconCard(
        icon: LucideIcons.percent,
        label: 'Resueltos por cada 100 que entran',
        // Salidas contra entradas del mismo periodo. Por encima de 100 se está
        // sacando más de lo que llega; por debajo, el montón crece.
        value: reportados.isEmpty
            ? '—'
            : '${(resueltos.length * 100 / reportados.length).round()} %',
        color: Colors.blue,
      ),
      KpiIconCard(
        icon: LucideIcons.hourglass,
        label: 'Caso abierto más viejo (todos)',
        value: masViejo == null ? '—' : '$masViejo días',
        color: masViejo != null && masViejo > 10 ? Colors.red : Colors.orange,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SelectorPeriodo(periodo: periodo, onChanged: onPeriodoChanged),
          const SizedBox(height: 12),
          _Tarjetas(children: tarjetas),
          const SizedBox(height: 20),
          _GraficaFlujo(dias: dias, periodo: periodo),
        ],
      ),
    );
  }
}

/// Desplegable de periodo, con la misma escalera de opciones que el Dashboard
/// para que las dos pantallas se elijan igual.
class _SelectorPeriodo extends StatefulWidget {
  const _SelectorPeriodo({required this.periodo, required this.onChanged});

  final PeriodoResumen periodo;
  final ValueChanged<PeriodoResumen> onChanged;

  @override
  State<_SelectorPeriodo> createState() => _SelectorPeriodoState();
}

class _SelectorPeriodoState extends State<_SelectorPeriodo> {
  /// Para abrir el calendario al elegir "Personalizado".
  final _menu = MenuController();

  PeriodoResumen get periodo => widget.periodo;
  ValueChanged<PeriodoResumen> get onChanged => widget.onChanged;

  void _elegir(BuildContext context, int indice) {
    if (indice != PeriodoResumen.indicePersonalizado) {
      onChanged(PeriodoResumen.preset(indice));
      return;
    }
    // Calendario desplegable, no ventana a pantalla completa.
    // Al siguiente cuadro: en este instante el desplegable todavía se está
    // cerrando, y abrir el calendario encima se pierde.
    WidgetsBinding.instance.addPostFrameCallback((_) => _menu.open());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hoy = DateTime.now();
    return CalendarioRangoMenu(
      controller: _menu,
      rango: DateTimeRange(start: periodo.inicio, end: periodo.fin),
      ultimoDia: DateTime(hoy.year, hoy.month, hoy.day),
      onChanged: (r) => onChanged(PeriodoResumen.personalizado(r)),
      builder: (context, _) => Row(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: colors.divider),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: periodo.indice,
                isDense: true,
                icon: Icon(
                  LucideIcons.chevronDown,
                  size: 16,
                  color: colors.textSecondary,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                dropdownColor: colors.surface,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                // Cerrado muestra el periodo de verdad, así que uno
                // personalizado se lee como las dos fechas que se eligieron y no
                // como la palabra "Personalizado", que no dice cuáles son.
                selectedItemBuilder: (_) => [
                  for (var i = 0; i < PeriodoResumen.etiquetas.length; i++)
                    Row(
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          size: 15,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          periodo.etiqueta,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                ],
                items: [
                  for (var i = 0; i < PeriodoResumen.etiquetas.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(PeriodoResumen.etiquetas[i]),
                    ),
                ],
                onChanged: (v) => v == null ? null : _elegir(context, v),
              ),
            ),
          ),
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
                  SizedBox(width: 200, child: children[i]),
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

/// Entradas contra salidas, día por día.
///
/// La única gráfica de la versión chica, y a propósito: es la que responde la
/// pregunta que ningún indicador suelto responde — si el trabajo entra más
/// rápido de lo que sale, el montón crece aunque todos los números del día se
/// vean bien.
class _GraficaFlujo extends StatelessWidget {
  const _GraficaFlujo({required this.dias, required this.periodo});

  final List<SupportDay> dias;
  final PeriodoResumen periodo;

  /// Texto del globo al pasar por un punto: el día arriba, la serie y su cifra
  /// abajo. Sin el día hay que contar columnas para saber cuál se está mirando.
  String _textoGlobo(LineBarSpot s) {
    final serie = s.barIndex == 0 ? 'Entraron' : 'Se resolvieron';
    final i = s.spotIndex;
    if (i < 0 || i >= dias.length) return '$serie: ${s.y.toInt()}';
    return '${formatDay(dias[i].day)}\n$serie: ${s.y.toInt()}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entradas = Colors.orange;
    final salidas = Colors.green;

    if (dias.isEmpty) {
      return const SizedBox.shrink();
    }

    final maximo = dias
        .expand((d) => [d.opened, d.resolved])
        .fold<int>(0, (a, b) => a > b ? a : b);
    // Con todo en cero el gráfico no tiene alto que repartir y fl_chart dibuja
    // una rejilla degenerada. Un techo mínimo lo mantiene legible y vacío, que
    // es la lectura correcta cuando de verdad no pasó nada.
    final techo = (maximo == 0 ? 4 : maximo + 1).toDouble();
    final paso = techo <= 5 ? 1.0 : (techo / 4).ceilToDouble();

    final totalEntradas = dias.fold<int>(0, (a, d) => a + d.opened);
    final totalSalidas = dias.fold<int>(0, (a, d) => a + d.resolved);
    final gana = totalSalidas >= totalEntradas;

    // Ocho marcas como mucho: con 30 días, una etiqueta por día se convierte en
    // una mancha negra. Se reparten parejas y la última siempre cae en el
    // último día, que es el que se busca primero.
    final maxMarcas = context.isMobile ? 4 : 8;
    final saltoEtiquetas = (dias.length / maxMarcas).ceil().clamp(1, 999);

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
            'Del ${formatDay(periodo.inicio)} al ${formatDay(periodo.fin)} · '
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
                // Medio paso de aire a cada lado. Sin esto la etiqueta del
                // último día se centra sobre el borde derecho y se corta a la
                // mitad.
                minX: -0.5,
                maxX: (dias.length - 1) + 0.5,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: paso,
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
                      interval: paso,
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
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (v, _) {
                        // Con medio paso de margen, fl_chart pide también las
                        // marcas de -0.5 y n-0.5, que no son ningún día.
                        if (v != v.roundToDouble()) {
                          return const SizedBox.shrink();
                        }
                        final i = v.toInt();
                        if (i < 0 || i >= dias.length) {
                          return const SizedBox.shrink();
                        }
                        final ultimo = i == dias.length - 1;
                        // Se cuenta desde el final para que la última quede
                        // siempre puesta: contando desde el principio, con 30
                        // días y salto 4 la última caía en el día 28 y el
                        // gráfico volvía a parecer cortado antes de hoy.
                        final desdeElFinal = dias.length - 1 - i;
                        if (!ultimo && desdeElFinal % saltoEtiquetas != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            formatDay(dias[i].day),
                            style: TextStyle(
                              color: ultimo
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                              fontSize: context.isMobile ? 9 : 10,
                              fontWeight: ultimo
                                  ? FontWeight.w600
                                  : FontWeight.normal,
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
                          _textoGlobo(s),
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
                  _linea([
                    for (var i = 0; i < dias.length; i++)
                      FlSpot(i.toDouble(), dias[i].opened.toDouble()),
                  ], entradas),
                  _linea([
                    for (var i = 0; i < dias.length; i++)
                      FlSpot(i.toDouble(), dias[i].resolved.toDouble()),
                  ], salidas),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Segmentos rectos, no curva: son casos contados por día. Una curva pasa por
  /// valores que ningún día tuvo y se sale por debajo de cero entre dos días
  /// flojos — dibuja un dato que no existe.
  LineChartBarData _linea(List<FlSpot> spots, Color color) => LineChartBarData(
    spots: spots,
    isCurved: false,
    color: color,
    barWidth: 2,
    // Con 30 días o más, un punto por día tapa la línea. Sólo se dibujan
    // cuando son pocos y cada uno se distingue.
    dotData: FlDotData(
      show: spots.length <= 14,
      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
        radius: 3,
        color: color,
        strokeWidth: 0,
        strokeColor: color,
      ),
    ),
    belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
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
