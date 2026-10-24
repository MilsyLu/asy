import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/requirement_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../models/requirement_model.dart';
import '../../services/requirement_repository.dart';
import '../../widgets/kpi_icon_card.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/single_column_grid.dart';
import 'requirement_create_panel.dart';
import 'requirement_detail_view.dart';
import 'requirement_widgets.dart';

/// Abre el formulario de requerimiento nuevo. Lo usa la barra superior.
void openRequirementCreateForm(BuildContext context) =>
    showRequirementCreateSheet(context);

enum _Vista { tabla, tablero }

/// Requerimientos: lo que los clientes piden que VinApp haga.
///
/// Reemplaza la hoja de cálculo que se compartía con el área de soporte. La
/// hoja tenía 48 filas y sus cinco últimas columnas —las del seguimiento de
/// QA— estaban vacías en las 48: el recorrido se acababa en "En Desarrollo" y
/// no había dónde anotar lo que pasaba después. Aquí ese recorrido llega
/// hasta "Comunicado al cliente", que es donde de verdad termina.
class RequirementsPage extends StatefulWidget {
  const RequirementsPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<RequirementsPage> createState() => _RequirementsPageState();
}

class _RequirementsPageState extends State<RequirementsPage> {
  final _buscador = TextEditingController();
  String _query = '';
  String? _estado;
  String? _modulo;
  String? _responsable;
  bool _soloAbiertos = true;
  _Vista _vista = _Vista.tabla;
  String? _seleccionado;

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  List<RequirementModel> _filtrar(List<RequirementModel> todos) {
    final q = _query.trim().toLowerCase();
    return todos.where((r) {
      if (_soloAbiertos && !r.estaAbierto) return false;
      if (_estado != null && r.status != _estado) return false;
      if (_modulo != null && r.module != _modulo) return false;
      if (_responsable != null) {
        if (_responsable == _sinResponsable) {
          if (r.estaAsignado) return false;
        } else if (r.developerId != _responsable) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      return r.description.toLowerCase().contains(q) ||
          r.paraQuien.toLowerCase().contains(q) ||
          r.module.toLowerCase().contains(q) ||
          r.type.toLowerCase().contains(q) ||
          r.developerName.toLowerCase().contains(q) ||
          r.codigo.toLowerCase().contains(q);
    }).toList()..sort((a, b) {
      // Primero por prioridad y, a igual prioridad, lo más viejo arriba:
      // un requerimiento de hace tres meses no debería quedar debajo del de
      // ayer sólo porque se registró después.
      final p = RequirementPriority.rank(
        b.priority,
      ).compareTo(RequirementPriority.rank(a.priority));
      if (p != 0) return p;
      return a.receivedAt.compareTo(b.receivedAt);
    });
  }

  static const String _sinResponsable = '__sin_responsable__';

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<RequirementRepository>();
    final isMobile = context.isMobile;

    final cuerpo = StreamBuilder<List<RequirementModel>>(
      stream: repo.watchAll(),
      builder: (context, snap) {
        if (snap.hasError) return StreamErrorState(error: snap.error!);
        if (!snap.hasData) return const LoadingIndicator();
        final todos = snap.data!;
        final lista = _filtrar(todos);

        final contenido = lista.isEmpty
            ? const EmptyState(
                message: 'No hay requerimientos que coincidan.',
                icon: LucideIcons.lightbulb,
              )
            : (!isMobile && _vista == _Vista.tablero)
            ? _Tablero(
                requerimientos: lista,
                onTap: (id) => setState(() => _seleccionado = id),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                itemCount: lista.length,
                itemBuilder: (_, i) => _Fila(
                  requerimiento: lista[i],
                  seleccionado: lista[i].id == _seleccionado,
                  onTap: () => setState(() => _seleccionado = lista[i].id),
                ),
              );

        final cabecera = _Cabecera(
          todos: todos,
          mostrados: lista.length,
          buscador: _buscador,
          onQuery: (v) => setState(() => _query = v),
          estado: _estado,
          onEstado: (v) => setState(() => _estado = v),
          modulo: _modulo,
          onModulo: (v) => setState(() => _modulo = v),
          responsable: _responsable,
          onResponsable: (v) => setState(() => _responsable = v),
          soloAbiertos: _soloAbiertos,
          onSoloAbiertos: (v) => setState(() => _soloAbiertos = v),
          vista: isMobile ? null : _vista,
          onVista: (v) => setState(() => _vista = v),
        );

        return LayoutBuilder(
          builder: (context, c) {
            final conPanel = c.maxWidth >= 1000 && _seleccionado != null;
            final columna = Column(
              children: [
                cabecera,
                Expanded(child: contenido),
              ],
            );
            if (!conPanel) return columna;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: columna),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: RequirementDetailView(
                    key: ValueKey(_seleccionado),
                    requirementId: _seleccionado!,
                    onClose: () => setState(() => _seleccionado = null),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (!widget.showAppBar) return cuerpo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requerimientos'),
        actions: [
          // Sin condición: registrar un requerimiento lo puede hacer
          // cualquiera que atienda al cliente. Lo que pide permiso es
          // aprobarlo y asignarlo, no anotarlo.
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Nuevo requerimiento',
            onPressed: () => showRequirementCreateSheet(context),
          ),
        ],
      ),
      body: cuerpo,
    );
  }
}

/// Indicadores, buscador y filtros.
class _Cabecera extends StatelessWidget {
  const _Cabecera({
    required this.todos,
    required this.mostrados,
    required this.buscador,
    required this.onQuery,
    required this.estado,
    required this.onEstado,
    required this.modulo,
    required this.onModulo,
    required this.responsable,
    required this.onResponsable,
    required this.soloAbiertos,
    required this.onSoloAbiertos,
    required this.vista,
    required this.onVista,
  });

  final List<RequirementModel> todos;
  final int mostrados;
  final TextEditingController buscador;
  final ValueChanged<String> onQuery;
  final String? estado;
  final ValueChanged<String?> onEstado;
  final String? modulo;
  final ValueChanged<String?> onModulo;
  final String? responsable;
  final ValueChanged<String?> onResponsable;
  final bool soloAbiertos;
  final ValueChanged<bool> onSoloAbiertos;
  final _Vista? vista;
  final ValueChanged<_Vista> onVista;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final abiertos = todos.where((r) => r.estaAbierto).toList();
    final sinAsignar = abiertos.where((r) => !r.estaAsignado).length;
    final enDesarrollo = todos
        .where((r) => RequirementStatus.enManosDeDesarrollo(r.status))
        .length;
    final sinAprobar = todos
        .where((r) => r.status == RequirementStatus.recibido)
        .length;
    final publicados = todos
        .where(
          (r) =>
              r.status == RequirementStatus.publicado ||
              r.status == RequirementStatus.comunicado,
        )
        .length;

    final responsables = <String, int>{};
    for (final r in todos) {
      responsables[r.estaAsignado
              ? r.developerId!
              : _RequirementsPageState._sinResponsable] =
          (responsables[r.estaAsignado
                  ? r.developerId!
                  : _RequirementsPageState._sinResponsable] ??
              0) +
          1;
    }
    final nombres = <String, String>{
      _RequirementsPageState._sinResponsable: 'Sin asignar',
      for (final r in todos)
        if (r.estaAsignado) r.developerId!: r.developerName,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final tarjetas = <Widget>[
                KpiIconCard(
                  icon: LucideIcons.inbox,
                  label: 'Sin aprobar',
                  value: '$sinAprobar',
                  color: Colors.blueGrey,
                  labelAbove: true,
                ),
                KpiIconCard(
                  icon: LucideIcons.lightbulb,
                  label: 'Abiertos',
                  value: '${abiertos.length}',
                  color: colors.primary,
                  labelAbove: true,
                ),
                KpiIconCard(
                  icon: LucideIcons.userX,
                  label: 'Sin responsable',
                  value: '$sinAsignar',
                  color: Colors.orange,
                  labelAbove: true,
                ),
                KpiIconCard(
                  icon: LucideIcons.hammer,
                  label: 'En desarrollo o QA',
                  value: '$enDesarrollo',
                  color: Colors.purple,
                  labelAbove: true,
                ),
                KpiIconCard(
                  icon: LucideIcons.checkCircle2,
                  label: 'Publicados',
                  value: '$publicados',
                  color: Colors.green,
                  labelAbove: true,
                ),
              ];
              final controles = <Widget>[
                if (vista != null)
                  SegmentedButton<_Vista>(
                    segments: const [
                      ButtonSegment(
                        value: _Vista.tabla,
                        label: Text('Lista'),
                        icon: Icon(LucideIcons.list, size: 15),
                      ),
                      ButtonSegment(
                        value: _Vista.tablero,
                        label: Text('Tablero'),
                        icon: Icon(LucideIcons.columns, size: 15),
                      ),
                    ],
                    selected: {vista!},
                    onSelectionChanged: (s) => onVista(s.first),
                    style: const ButtonStyle(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ];

              if (c.maxWidth < 1100) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Tira(children: tarjetas),
                    if (controles.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _Tira(children: controles),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < tarjetas.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: tarjetas[i]),
                  ],
                  if (controles.isNotEmpty) ...[
                    const SizedBox(width: 16),
                    ...controles,
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final angosto = c.maxWidth < 900;
              final campo = TextField(
                controller: buscador,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar por cliente, texto, módulo o REQ-…',
                  prefixIcon: Icon(
                    LucideIcons.search,
                    color: colors.primary,
                    size: 18,
                  ),
                ),
                onChanged: onQuery,
              );
              final filtros = <Widget>[
                _filtro(
                  context,
                  'Estado',
                  estado,
                  RequirementStatus.all,
                  onEstado,
                  'Todos los estados',
                ),
                _filtro(
                  context,
                  'Módulo',
                  modulo,
                  RequirementModule.all,
                  onModulo,
                  'Todos los módulos',
                ),
                DropdownButton<String?>(
                  value: responsable,
                  underline: const SizedBox.shrink(),
                  hint: const Text('Responsable'),
                  onChanged: onResponsable,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos los responsables'),
                    ),
                    for (final e in responsables.entries)
                      DropdownMenuItem<String?>(
                        value: e.key,
                        child: Text('${nombres[e.key] ?? '—'} (${e.value})'),
                      ),
                  ],
                ),
                FilterChip(
                  label: const Text('Solo abiertos'),
                  selected: soloAbiertos,
                  onSelected: onSoloAbiertos,
                ),
              ];

              if (angosto) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    campo,
                    const SizedBox(height: 8),
                    _Tira(children: filtros),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 320, child: campo),
                  const SizedBox(width: 12),
                  Expanded(
                    // Centrado: un `FilterChip` es más bajo que un
                    // desplegable, y sin esto se apoyaba en el borde de
                    // arriba y se veía desalineado.
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: filtros,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            '$mostrados de ${todos.length} requerimientos',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _filtro(
    BuildContext context,
    String titulo,
    String? valor,
    List<String> opciones,
    ValueChanged<String?> onChanged,
    String todos,
  ) {
    return DropdownButton<String?>(
      value: valor,
      underline: const SizedBox.shrink(),
      hint: Text(titulo),
      onChanged: onChanged,
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(todos)),
        for (final o in opciones)
          DropdownMenuItem<String?>(value: o, child: Text(o)),
      ],
    );
  }
}

/// Una fila deslizable: lo mismo que en Casos de Soporte, por la misma razón.
class _Tira extends StatelessWidget {
  const _Tira({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Una fila de la lista.
class _Fila extends StatelessWidget {
  const _Fila({
    required this.requerimiento,
    required this.seleccionado,
    required this.onTap,
  });

  final RequirementModel requerimiento;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final r = requerimiento;
    // La descripción es lo único que estaba lleno en las 48 filas de la hoja,
    // así que es lo que se muestra: dos líneas alcanzan para reconocerlo.
    final resumen = r.description.replaceAll('\n', ' ').trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: seleccionado
                ? colors.primary.withValues(alpha: 0.07)
                : colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: seleccionado ? colors.primary : colors.divider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${r.codigo} · ${r.paraQuien}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RequirementBadge.estado(r.status, dense: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                resumen,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  RequirementBadge.tipo(r.type, dense: true),
                  RequirementBadge.prioridad(r.priority, dense: true),
                  RequirementModuleChip(module: r.module),
                  Text(
                    r.estaAsignado ? r.developerName : 'Sin responsable',
                    style: TextStyle(
                      color: r.estaAsignado
                          ? colors.textSecondary
                          : Colors.orange,
                      fontSize: 11,
                      fontWeight: r.estaAsignado
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                  Text(
                    AppDateUtils.formatShortDate(r.receivedAt),
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El tablero: una columna por paso del recorrido.
///
/// Las columnas se reparten el ancho en vez de medir lo mismo siempre: con
/// siete columnas de 260 px el tablero pedía más de 1.800 y había que
/// desplazarse de lado para ver el final del flujo, que es justo lo que uno
/// quiere mirar de un vistazo. Cada columna se desplaza por dentro cuando
/// tiene muchas tarjetas, así el tablero entero cabe en la pantalla.
///
/// Sólo el camino principal tiene columna propia. "En pausa" y "Rechazado" no
/// son etapas sino salidas, y van juntos al final: ponerlos en la fila haría
/// parecer que todo termina ahí.
class _Tablero extends StatelessWidget {
  const _Tablero({required this.requerimientos, required this.onTap});

  final List<RequirementModel> requerimientos;
  final void Function(String id) onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final columnas =
        <({String titulo, List<RequirementModel> items, Color? color})>[
          for (final estado in RequirementStatus.flujo)
            (
              titulo: estado,
              items: requerimientos.where((r) => r.status == estado).toList(),
              color: null,
            ),
          (
            titulo: 'Fuera del flujo',
            items: requerimientos
                .where(
                  (r) =>
                      r.status == RequirementStatus.enPausa ||
                      r.status == RequirementStatus.rechazado,
                )
                .toList(),
            color: colors.textSecondary,
          ),
        ];

    // Con un filtro puesto, lo normal es que sólo una columna tenga algo: el
    // tablero deja de ser un tablero y queda una tira angosta con seis
    // columnas vacías al lado, desperdiciando la pantalla entera. En ese caso
    // las tarjetas se reparten en rejilla a todo el ancho, que es lo que uno
    // espera ver cuando ya eligió el estado que quería mirar.
    final conItems = [
      for (final c in columnas)
        if (c.items.isNotEmpty) c,
    ];
    if (conItems.length == 1) {
      final unica = conItems.first;
      return SingleColumnGrid(
        titulo: unica.titulo,
        color: unica.color ?? RequirementStatus.colorFor(unica.titulo),
        cantidad: unica.items.length,
        itemBuilder: (_, i) => _Tarjeta(
          requerimiento: unica.items[i],
          onTap: () => onTap(unica.items[i].id),
          enColumna: false,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        // Por debajo de esto, repartir el ancho dejaría columnas de menos de
        // 150 px, donde un nombre de cliente no cabe ni cortado. Ahí sí se
        // desliza, que es preferible a siete columnas ilegibles.
        final reparte = c.maxWidth >= 1080;

        Widget columna(
          ({String titulo, List<RequirementModel> items, Color? color}) col,
        ) => _Columna(
          estado: col.titulo,
          items: col.items,
          onTap: onTap,
          color: col.color,
        );

        if (reparte) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < columnas.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: columna(columnas[i])),
                ],
              ],
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < columnas.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                SizedBox(width: 260, child: columna(columnas[i])),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna({
    required this.estado,
    required this.items,
    required this.onTap,
    this.color,
  });

  final String estado;
  final List<RequirementModel> items;
  final void Function(String id) onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = color ?? RequirementStatus.colorFor(estado);

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
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  estado,
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
                '${items.length}',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Cada columna se desplaza por dentro. Antes las tarjetas crecían
          // hacia abajo sin límite y las últimas quedaban cortadas contra el
          // borde de la pantalla, sin forma de llegar a ellas.
          Expanded(
            child: items.isEmpty
                ? Text(
                    'Sin requerimientos',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (_, i) => _Tarjeta(
                      requerimiento: items[i],
                      onTap: () => onTap(items[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.requerimiento,
    required this.onTap,
    this.enColumna = true,
  });

  final RequirementModel requerimiento;
  final VoidCallback onTap;

  /// En una columna la tarjeta pone su propia separación; en la rejilla no,
  /// porque ahí el espaciado lo maneja el `GridView` y los dos juntos dejan
  /// un hueco doble entre filas.
  final bool enColumna;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final r = requerimiento;
    return Padding(
      padding: EdgeInsets.only(bottom: enColumna ? 8 : 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: colors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.codigo,
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
              Text(
                r.paraQuien,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                r.description.replaceAll('\n', ' ').trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  RequirementBadge.prioridad(r.priority, dense: true),
                  if (r.estaAsignado)
                    RequirementModuleChip(module: r.developerName),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
