import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/task_repository.dart';
import '../../widgets/loading_indicator.dart';
import '../home/widgets/compact_task_card.dart';
import '../home/widgets/task_detail_dialog.dart';

/// Cómo se reparte la pantalla: por día, por semana o el mes de una persona.
enum _Modo { dia, semana, mes }

/// El calendario visto por encargado: quién tiene qué.
///
/// Las vistas de Mes y Semana que ya existían contestan "qué hay ese día".
/// Ésta contesta la otra mitad —"quién lo tiene, y quién está libre"— que es
/// lo que hace falta para repartir trabajo, y que hasta ahora obligaba a
/// abrir tarea por tarea para ver el encargado.
///
/// Los tres modos no son tres pantallas: son la misma pregunta mirada a tres
/// distancias. El día sirve para despachar hoy, la semana para ver quién está
/// cargado, y el mes para seguir a una persona.
class ByAssigneePage extends StatefulWidget {
  const ByAssigneePage({super.key});

  @override
  State<ByAssigneePage> createState() => _ByAssigneePageState();
}

class _ByAssigneePageState extends State<ByAssigneePage> {
  _Modo _modo = _Modo.dia;
  DateTime _ancla = DateTime.now();
  String? _persona;
  bool _personaInicializada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Arranca en quien está consultando: lo más común es querer ver lo
    // propio, y obligar a elegirse a uno mismo en una lista es un paso que
    // la app puede dar sola. Va aquí y no en initState porque el usuario
    // llega por provider, que no se puede leer antes.
    if (_personaInicializada) return;
    _personaInicializada = true;
    _persona = context.read<AuthProvider>().appUser?.id;
  }

  DateTime get _desde => switch (_modo) {
    _Modo.dia => DateTime(_ancla.year, _ancla.month, _ancla.day),
    _Modo.semana => _lunesDe(_ancla),
    _Modo.mes => DateTime(_ancla.year, _ancla.month, 1),
  };

  DateTime get _hasta => switch (_modo) {
    _Modo.dia => DateTime(_ancla.year, _ancla.month, _ancla.day),
    _Modo.semana => _lunesDe(_ancla).add(const Duration(days: 6)),
    // Día 0 del mes siguiente es el último del actual, y acierta en febrero
    // y en los meses de 31 sin tener que saber cuál es cuál.
    _Modo.mes => DateTime(_ancla.year, _ancla.month + 1, 0),
  };

  static DateTime _lunesDe(DateTime d) {
    final dia = DateTime(d.year, d.month, d.day);
    return dia.subtract(Duration(days: dia.weekday - DateTime.monday));
  }

  void _mover(int pasos) {
    setState(() {
      _ancla = switch (_modo) {
        _Modo.dia => _ancla.add(Duration(days: pasos)),
        _Modo.semana => _ancla.add(Duration(days: 7 * pasos)),
        _Modo.mes => DateTime(_ancla.year, _ancla.month + pasos, 1),
      };
    });
  }

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: _ancla,
      firstDate: DateTime(hoy.year - 3),
      lastDate: DateTime(hoy.year + 3),
      helpText: switch (_modo) {
        _Modo.dia => 'Elige el día',
        _Modo.semana => 'Elige un día de la semana',
        _Modo.mes => 'Elige un día del mes',
      },
      // En modo mes se empieza por el año: lo que se busca es el mes, y
      // llegar a él desde la rejilla de días es dar vueltas de más.
      initialDatePickerMode: _modo == _Modo.mes
          ? DatePickerMode.year
          : DatePickerMode.day,
    );
    if (elegida == null || !mounted) return;
    setState(() => _ancla = elegida);
  }

  String get _titulo => switch (_modo) {
    _Modo.dia => AppDateUtils.formatHumanDate(_ancla),
    _Modo.semana =>
      '${AppDateUtils.formatDayMonth(_desde)} — '
          '${AppDateUtils.formatDayMonth(_hasta)}',
    _Modo.mes => AppDateUtils.formatHeaderDate(_ancla),
  };

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TaskRepository>();
    final catalog = context.watch<CatalogProvider>();
    final colors = context.colors;

    final personas = [
      for (final u in catalog.users)
        if (u.isActive) u,
    ]..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _barra(colors, personas),
        const Divider(height: 1),
        Expanded(
          child: StreamBuilder<List<TaskModel>>(
            // La clave fuerza un stream nuevo al cambiar el rango; sin ella
            // seguiría escuchando el periodo anterior.
            key: ValueKey(
              '${_desde.toIso8601String()}|${_hasta.toIso8601String()}',
            ),
            stream: repo.watchTasksInRange(_desde, _hasta),
            builder: (context, snap) {
              if (snap.hasError) return StreamErrorState(error: snap.error!);
              if (!snap.hasData) return const LoadingIndicator();
              final tareas = [
                for (final t in snap.data!)
                  if (!t.isDeleted) t,
              ];
              return switch (_modo) {
                _Modo.dia => _VistaDia(tareas: tareas, personas: personas),
                _Modo.semana => _VistaSemana(
                  tareas: tareas,
                  personas: personas,
                  lunes: _desde,
                ),
                _Modo.mes => _VistaMes(
                  tareas: tareas,
                  mes: _ancla,
                  personaId: _persona,
                ),
              };
            },
          ),
        ),
      ],
    );
  }

  Widget _barra(AppColorsExtension colors, List<AppUser> personas) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SegmentedButton<_Modo>(
            segments: const [
              ButtonSegment(value: _Modo.dia, label: Text('Día')),
              ButtonSegment(value: _Modo.semana, label: Text('Semana')),
              ButtonSegment(value: _Modo.mes, label: Text('Una persona')),
            ],
            selected: {_modo},
            onSelectionChanged: (s) => setState(() => _modo = s.first),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Anterior',
                icon: const Icon(LucideIcons.chevronLeft, size: 18),
                onPressed: () => _mover(-1),
              ),
              // El título abre el calendario. Las flechas sirven para
              // moverse un paso; saltar a otro mes con ellas son veinte
              // clics, y el texto de la fecha es justo donde uno intenta
              // hacer clic para eso.
              InkWell(
                onTap: _elegirFecha,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _titulo,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        LucideIcons.calendar,
                        size: 14,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Siguiente',
                icon: const Icon(LucideIcons.chevronRight, size: 18),
                onPressed: () => _mover(1),
              ),
              TextButton(
                onPressed: () => setState(() => _ancla = DateTime.now()),
                child: const Text('Hoy'),
              ),
            ],
          ),
          // Sólo el modo de una persona necesita elegirla; en los otros dos
          // las personas son las columnas o las filas.
          if (_modo == _Modo.mes)
            DropdownButton<String?>(
              value: personas.any((p) => p.id == _persona) ? _persona : null,
              hint: const Text('Elige un encargado'),
              underline: const SizedBox.shrink(),
              onChanged: (v) => setState(() => _persona = v),
              items: [
                for (final p in personas)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Día: una columna por persona ─────────────────────────────────────────

class _VistaDia extends StatelessWidget {
  const _VistaDia({required this.tareas, required this.personas});

  final List<TaskModel> tareas;
  final List<AppUser> personas;

  @override
  Widget build(BuildContext context) {
    final porPersona = <String, List<TaskModel>>{
      for (final p in personas) p.id: [],
    };
    final sinAsignar = <TaskModel>[];
    for (final t in tareas) {
      final lista = porPersona[t.assignedUserId];
      if (lista == null) {
        sinAsignar.add(t);
      } else {
        lista.add(t);
      }
    }
    for (final l in porPersona.values) {
      l.sort((a, b) => a.hour.compareTo(b.hour));
    }
    sinAsignar.sort((a, b) => a.hour.compareTo(b.hour));

    final columnas = <({String nombre, List<TaskModel> tareas})>[
      for (final p in personas) (nombre: p.name, tareas: porPersona[p.id]!),
      // Las huérfanas no se esconden: una tarea de alguien que ya no está en
      // el equipo seguiría agendada y sin aparecer en ninguna columna.
      if (sinAsignar.isNotEmpty) (nombre: 'Sin asignar', tareas: sinAsignar),
    ];

    if (columnas.isEmpty) {
      return const EmptyState(
        message: 'No hay encargados activos.',
        icon: LucideIcons.users,
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        // Por debajo de 180 px por columna el nombre del cliente no se lee;
        // ahí se deslizan de lado en vez de apretarse.
        final reparte = c.maxWidth / columnas.length >= 180;
        final contenido = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columnas.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              if (reparte)
                Expanded(child: _ColumnaPersona(columna: columnas[i]))
              else
                SizedBox(
                  width: 240,
                  child: _ColumnaPersona(columna: columnas[i]),
                ),
            ],
          ],
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: reparte
              ? contenido
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: columnas.length * 248,
                    child: contenido,
                  ),
                ),
        );
      },
    );
  }
}

class _ColumnaPersona extends StatelessWidget {
  const _ColumnaPersona({required this.columna});

  final ({String nombre, List<TaskModel> tareas}) columna;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  columna.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '${columna.tareas.length}',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: columna.tareas.isEmpty
                // Decirlo importa: una columna vacía es la respuesta a
                // "¿quién está libre?", no un hueco.
                ? Text(
                    'Libre',
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: columna.tareas.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () =>
                          showTaskDetailDialog(context, columna.tareas[i]),
                      child: CompactTaskCard(task: columna.tareas[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Semana: una fila por persona ─────────────────────────────────────────

class _VistaSemana extends StatelessWidget {
  const _VistaSemana({
    required this.tareas,
    required this.personas,
    required this.lunes,
  });

  final List<TaskModel> tareas;
  final List<AppUser> personas;
  final DateTime lunes;

  static const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fechas = [for (var i = 0; i < 7; i++) lunes.add(Duration(days: i))];

    // (persona, día) -> cuántas
    final conteo = <String, Map<String, int>>{};
    for (final t in tareas) {
      final porDia = conteo.putIfAbsent(t.assignedUserId, () => {});
      porDia[t.date] = (porDia[t.date] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 150),
              for (final f in fechas)
                Expanded(
                  child: Center(
                    child: Text(
                      '${_dias[f.weekday - 1]} ${f.day}',
                      style: TextStyle(
                        color: AppDateUtils.isSameDay(f, DateTime.now())
                            ? colors.primary
                            : colors.textSecondary,
                        fontWeight: AppDateUtils.isSameDay(f, DateTime.now())
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 56),
            ],
          ),
          const SizedBox(height: 6),
          for (final p in personas) ...[
            _FilaSemana(
              nombre: p.name,
              fechas: fechas,
              porDia: conteo[p.id] ?? const {},
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _FilaSemana extends StatelessWidget {
  const _FilaSemana({
    required this.nombre,
    required this.fechas,
    required this.porDia,
  });

  final String nombre;
  final List<DateTime> fechas;
  final Map<String, int> porDia;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = porDia.values.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.divider),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          for (final f in fechas)
            Expanded(
              child: Center(
                child: _Celda(
                  cantidad: porDia[AppDateUtils.formatDateKey(f)] ?? 0,
                ),
              ),
            ),
          SizedBox(
            width: 56,
            child: Text(
              total == 0 ? '—' : '$total',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: total == 0 ? colors.textSecondary : colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La casilla de un día: cuántas tareas, con el fondo más fuerte cuanto más
/// cargado. El color es lo que deja ver el reparto sin leer los números.
class _Celda extends StatelessWidget {
  const _Celda({required this.cantidad});

  final int cantidad;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (cantidad == 0) {
      return Text('·', style: TextStyle(color: colors.divider, fontSize: 16));
    }
    final fuerza = (cantidad.clamp(1, 5)) / 5;
    return Container(
      width: 30,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10 + fuerza * 0.28),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        '$cantidad',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Mes de una persona ───────────────────────────────────────────────────

class _VistaMes extends StatelessWidget {
  const _VistaMes({
    required this.tareas,
    required this.mes,
    required this.personaId,
  });

  final List<TaskModel> tareas;
  final DateTime mes;
  final String? personaId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (personaId == null) {
      return const EmptyState(
        message: 'Elige un encargado arriba para ver su mes.',
        icon: LucideIcons.userCheck,
      );
    }

    final suyas = [
      for (final t in tareas)
        if (t.assignedUserId == personaId) t,
    ];
    final porDia = <String, List<TaskModel>>{};
    for (final t in suyas) {
      porDia.putIfAbsent(t.date, () => []).add(t);
    }

    final primero = DateTime(mes.year, mes.month, 1);
    final ultimo = DateTime(mes.year, mes.month + 1, 0);
    // Celdas en blanco hasta el primer día, para que las columnas caigan en
    // su día de la semana.
    final huecos = primero.weekday - DateTime.monday;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${suyas.length} ${suyas.length == 1 ? 'tarea' : 'tareas'} en el mes',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final d in _VistaSemana._dias)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              mainAxisExtent: 76,
            ),
            itemCount: huecos + ultimo.day,
            itemBuilder: (_, i) {
              if (i < huecos) return const SizedBox.shrink();
              final dia = DateTime(mes.year, mes.month, i - huecos + 1);
              final delDia =
                  porDia[AppDateUtils.formatDateKey(dia)] ?? const [];
              return _CeldaMes(dia: dia, tareas: delDia);
            },
          ),
        ],
      ),
    );
  }
}

class _CeldaMes extends StatelessWidget {
  const _CeldaMes({required this.dia, required this.tareas});

  final DateTime dia;
  final List<TaskModel> tareas;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hoy = AppDateUtils.isSameDay(dia, DateTime.now());
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: hoy ? colors.primary : colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${dia.day}',
            style: TextStyle(
              color: hoy ? colors.primary : colors.textSecondary,
              fontSize: 11,
              fontWeight: hoy ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: tareas.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => showTaskDetailDialog(context, tareas[i]),
                child: _LineaTarea(tarea: tareas[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una tarea dentro de una celda del mes: punto del color de su estado, hora
/// y cliente.
///
/// El color es el mismo que usan la tarjeta compacta y el Kanban —ámbar
/// pendiente, verde completada, azul reprogramada— así que el mes se lee con
/// el mismo código que el resto de la app, sin aprender uno nuevo.
class _LineaTarea extends StatelessWidget {
  const _LineaTarea({required this.tarea});

  final TaskModel tarea;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    final color = taskStatusColor(colors, catalog.statusName(tarea.statusId));
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${tarea.hour} ',
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: tarea.clientName,
                    style: TextStyle(color: colors.textPrimary),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
