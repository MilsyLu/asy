/// El calendario que se despliega pegado a lo que uno toca.
///
/// Reemplaza a `showDateRangePicker` y `showDatePicker` en los filtros de la
/// app. Esas dos abren una ventana a pantalla completa, y Michel lo dijo
/// claro mirando la de Casos de Soporte: para elegir dos días no hace falta
/// sacar al usuario de donde está.
///
/// Está aquí y no copiado en cada pantalla porque son cinco filtros de fecha
/// —Dashboard, Reportes, Resumen de casos, Casos, Requerimientos— y el
/// calendario por encargado. Seis copias del mismo calendario es la forma
/// más segura de que dentro de un mes se vean distintos entre sí.
///
/// Dos formas, el mismo panel: [CalendarioRangoMenu] para un rango de días y
/// [CalendarioDiaMenu] para uno solo.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';
import '../core/utils/date_utils.dart';

/// Un atajo del panel: "Últimos 7 días" y compañía.
typedef AtajoFecha = ({String nombre, DateTimeRange rango});

/// Los atajos de siempre, calculados sobre hoy.
///
/// Son el 90 % de lo que uno pregunta, así que van arriba y resuelven el
/// filtro de un clic, sin tocar el calendario.
List<AtajoFecha> atajosHabituales({DateTime? hoy}) {
  final dia = AppDateUtils.soloDia(hoy ?? DateTime.now());
  return [
    (nombre: 'Hoy', rango: DateTimeRange(start: dia, end: dia)),
    (
      nombre: 'Últimos 7 días',
      rango: DateTimeRange(
        start: dia.subtract(const Duration(days: 6)),
        end: dia,
      ),
    ),
    (
      nombre: 'Últimos 30 días',
      rango: DateTimeRange(
        start: dia.subtract(const Duration(days: 29)),
        end: dia,
      ),
    ),
    (
      nombre: 'Este mes',
      rango: DateTimeRange(start: DateTime(dia.year, dia.month, 1), end: dia),
    ),
  ];
}

/// Elige un rango de días desde un calendario desplegable.
///
/// [builder] dibuja lo que se toca para abrirlo —un chip, un botón, lo que
/// sea— y recibe el controlador para abrir y cerrar el panel. Así cada
/// pantalla conserva el aspecto que ya tenía y sólo cambia el calendario.
class CalendarioRangoMenu extends StatefulWidget {
  const CalendarioRangoMenu({
    super.key,
    required this.rango,
    required this.onChanged,
    required this.builder,
    this.controller,
    this.atajos,
    this.primerDia,
    this.ultimoDia,
  });

  final DateTimeRange? rango;
  final ValueChanged<DateTimeRange> onChanged;
  final Widget Function(BuildContext context, MenuController controller)
  builder;

  /// Para abrirlo desde afuera (por ejemplo, al elegir "Personalizado" en un
  /// selector de periodos que ya existe).
  final MenuController? controller;

  /// Null = [atajosHabituales]. Una lista vacía los quita.
  final List<AtajoFecha>? atajos;

  final DateTime? primerDia;
  final DateTime? ultimoDia;

  @override
  State<CalendarioRangoMenu> createState() => _CalendarioRangoMenuState();
}

class _CalendarioRangoMenuState extends State<CalendarioRangoMenu> {
  late final MenuController _menu = widget.controller ?? MenuController();

  /// El primer día mientras todavía falta elegir el segundo.
  DateTime? _desde;

  @override
  Widget build(BuildContext context) {
    return _PanelMenu(
      controller: _menu,
      panel: (colors) => _Panel(
        atajos: widget.atajos ?? atajosHabituales(),
        onAtajo: (r) {
          setState(() => _desde = null);
          widget.onChanged(r);
          _menu.close();
        },
        pista: _desde == null
            ? 'O elige el primer día en el calendario'
            : 'Desde ${AppDateUtils.formatShortDate(_desde!)} · '
                  'ahora elige el último día',
        calendario: _Calendario(
          enfocado: _desde ?? widget.rango?.start,
          inicio: _desde ?? widget.rango?.start,
          fin: _desde == null ? widget.rango?.end : null,
          primerDia: widget.primerDia,
          ultimoDia: widget.ultimoDia,
          onDia: _elegir,
        ),
      ),
      builder: widget.builder,
      onAbrir: () => setState(() => _desde = null),
    );
  }

  /// Primer toque: el día de inicio. Segundo: el de fin, y se cierra.
  void _elegir(DateTime dia) {
    if (_desde == null) {
      setState(() => _desde = dia);
      return;
    }
    // Al revés también vale: tocar primero un día y después uno anterior
    // ordena el rango en vez de no hacer nada, que es lo que uno espera.
    final a = _desde!;
    final rango = dia.isBefore(a)
        ? DateTimeRange(start: dia, end: a)
        : DateTimeRange(start: a, end: dia);
    setState(() => _desde = null);
    widget.onChanged(rango);
    _menu.close();
  }
}

/// Elige un solo día desde un calendario desplegable.
class CalendarioDiaMenu extends StatefulWidget {
  const CalendarioDiaMenu({
    super.key,
    required this.dia,
    required this.onChanged,
    required this.builder,
    this.controller,
    this.atajos = const [],
    this.primerDia,
    this.ultimoDia,
  });

  final DateTime? dia;
  final ValueChanged<DateTime> onChanged;
  final Widget Function(BuildContext context, MenuController controller)
  builder;
  final MenuController? controller;

  /// Atajos que devuelven un día suelto, por ejemplo "Hoy".
  final List<({String nombre, DateTime dia})> atajos;

  final DateTime? primerDia;
  final DateTime? ultimoDia;

  @override
  State<CalendarioDiaMenu> createState() => _CalendarioDiaMenuState();
}

class _CalendarioDiaMenuState extends State<CalendarioDiaMenu> {
  late final MenuController _menu = widget.controller ?? MenuController();

  @override
  Widget build(BuildContext context) {
    return _PanelMenu(
      controller: _menu,
      panel: (colors) => _Panel(
        atajos: const [],
        atajosDia: widget.atajos,
        onAtajoDia: (d) {
          widget.onChanged(d);
          _menu.close();
        },
        pista: null,
        calendario: _Calendario(
          enfocado: widget.dia,
          seleccionado: widget.dia,
          primerDia: widget.primerDia,
          ultimoDia: widget.ultimoDia,
          onDia: (d) {
            widget.onChanged(d);
            _menu.close();
          },
        ),
      ),
      builder: widget.builder,
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Las piezas de adentro
// ───────────────────────────────────────────────────────────────────────────

class _PanelMenu extends StatelessWidget {
  const _PanelMenu({
    required this.controller,
    required this.panel,
    required this.builder,
    this.onAbrir,
  });

  final MenuController controller;
  final Widget Function(AppColorsExtension colors) panel;
  final Widget Function(BuildContext context, MenuController controller)
  builder;
  final VoidCallback? onAbrir;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MenuAnchor(
      controller: controller,
      // Sin desenfoque detrás: el panel es opaco y con eso basta.
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            side: BorderSide(color: colors.divider),
          ),
        ),
      ),
      // `onOpen` y no un envoltorio que espíe los toques: el panel tiene
      // que arrancar limpio se abra desde donde se abra, incluso cuando otra
      // pantalla lo abre sola al elegir "Personalizado".
      onOpen: onAbrir,
      menuChildren: [SizedBox(width: 330, child: panel(colors))],
      builder: (context, ctrl, _) => builder(context, ctrl),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.atajos,
    required this.calendario,
    required this.pista,
    this.onAtajo,
    this.atajosDia = const [],
    this.onAtajoDia,
  });

  final List<AtajoFecha> atajos;
  final ValueChanged<DateTimeRange>? onAtajo;
  final List<({String nombre, DateTime dia})> atajosDia;
  final ValueChanged<DateTime>? onAtajoDia;
  final String? pista;
  final Widget calendario;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hayAtajos = atajos.isNotEmpty || atajosDia.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hayAtajos) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in atajos)
                  _Atajo(nombre: a.nombre, onTap: () => onAtajo?.call(a.rango)),
                for (final a in atajosDia)
                  _Atajo(
                    nombre: a.nombre,
                    onTap: () => onAtajoDia?.call(a.dia),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.divider),
          ],
          if (pista != null) ...[
            const SizedBox(height: 6),
            Text(
              pista!,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ],
          calendario,
        ],
      ),
    );
  }
}

class _Atajo extends StatelessWidget {
  const _Atajo({required this.nombre, required this.onTap});

  final String nombre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          nombre,
          style: TextStyle(
            color: colors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _Calendario extends StatelessWidget {
  const _Calendario({
    required this.onDia,
    this.enfocado,
    this.inicio,
    this.fin,
    this.seleccionado,
    this.primerDia,
    this.ultimoDia,
  });

  final ValueChanged<DateTime> onDia;
  final DateTime? enfocado;
  final DateTime? inicio;
  final DateTime? fin;
  final DateTime? seleccionado;
  final DateTime? primerDia;
  final DateTime? ultimoDia;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hoy = DateTime.now();
    final desde = primerDia ?? DateTime.utc(hoy.year - 3, 1, 1);
    final hasta = ultimoDia ?? DateTime.utc(hoy.year + 2, 12, 31);
    // Un día enfocado fuera de los límites revienta el calendario.
    var centro = enfocado ?? hoy;
    if (centro.isBefore(desde)) centro = desde;
    if (centro.isAfter(hasta)) centro = hasta;

    return TableCalendar<void>(
      locale: 'es_ES',
      firstDay: desde,
      lastDay: hasta,
      focusedDay: centro,
      rangeStartDay: inicio,
      rangeEndDay: fin,
      selectedDayPredicate: seleccionado == null
          ? null
          : (d) => isSameDay(d, seleccionado),
      // El rango se arma a mano y no con el modo del paquete, para poder
      // cerrar el panel en cuanto queda completo: un día, otro día, listo.
      rangeSelectionMode: inicio == null && seleccionado != null
          ? RangeSelectionMode.toggledOff
          : RangeSelectionMode.toggledOn,
      daysOfWeekHeight: 18,
      rowHeight: 34,
      availableGestures: AvailableGestures.horizontalSwipe,
      onDaySelected: (dia, _) => onDia(AppDateUtils.soloDia(dia)),
      headerStyle: HeaderStyle(
        formatButtonVisible: false,
        titleCentered: true,
        headerPadding: const EdgeInsets.symmetric(vertical: 4),
        titleTextStyle: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        leftChevronIcon: Icon(
          LucideIcons.chevronLeft,
          color: colors.primary,
          size: 18,
        ),
        rightChevronIcon: Icon(
          LucideIcons.chevronRight,
          color: colors.primary,
          size: 18,
        ),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: TextStyle(color: colors.textSecondary, fontSize: 11),
        weekendStyle: TextStyle(color: colors.textSecondary, fontSize: 11),
      ),
      calendarStyle: CalendarStyle(
        defaultTextStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
        weekendTextStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
        outsideTextStyle: TextStyle(color: colors.textSecondary, fontSize: 12),
        todayDecoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        todayTextStyle: TextStyle(color: colors.primary, fontSize: 12),
        selectedDecoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
        rangeStartDecoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
        rangeEndDecoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
        withinRangeTextStyle: TextStyle(
          color: colors.textPrimary,
          fontSize: 12,
        ),
        rangeHighlightColor: colors.primary.withValues(alpha: 0.12),
      ),
    );
  }
}

/// El botón redondo de siempre para un filtro de fecha.
///
/// Lo usan Casos de Soporte y Requerimientos. Sin rango dice [etiquetaVacia];
/// con rango dice los dos días y trae la equis para soltarlo, porque un
/// filtro puesto que no se ve cómo quitar es la forma más rápida de que
/// alguien crea que se le perdieron las cosas.
class ChipFecha extends StatelessWidget {
  const ChipFecha({
    super.key,
    required this.rango,
    required this.onChanged,
    this.etiquetaVacia = 'Fecha',
  });

  final DateTimeRange? rango;
  final ValueChanged<DateTimeRange?> onChanged;
  final String etiquetaVacia;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final puesto = rango != null;
    final texto = puesto
        ? '${AppDateUtils.formatShortDate(rango!.start)} – '
              '${AppDateUtils.formatShortDate(rango!.end)}'
        : etiquetaVacia;

    return CalendarioRangoMenu(
      rango: rango,
      onChanged: (r) => onChanged(r),
      builder: (context, controller) => GestureDetector(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: Container(
          padding: EdgeInsets.only(
            left: 11,
            right: puesto ? 4 : 11,
            top: 6,
            bottom: 6,
          ),
          decoration: BoxDecoration(
            color: puesto ? colors.primary : colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: puesto ? colors.primary : colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.calendar,
                size: 13,
                color: puesto ? colors.onPrimary : colors.textSecondary,
              ),
              const SizedBox(width: 5),
              Text(
                texto,
                style: TextStyle(
                  color: puesto ? colors.onPrimary : colors.textSecondary,
                  fontSize: 12,
                  fontWeight: puesto ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (puesto)
                IconButton(
                  tooltip: 'Quitar el filtro de fecha',
                  onPressed: () => onChanged(null),
                  icon: Icon(LucideIcons.x, size: 13, color: colors.onPrimary),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 22,
                    minHeight: 22,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
