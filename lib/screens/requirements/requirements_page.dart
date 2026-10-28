import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/requirement_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/requirement_metrics.dart';
import '../../widgets/calendario_menu.dart';
import '../../widgets/ventana_flotante.dart';
import '../../core/utils/support_case_metrics.dart';
import '../../models/requirement_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/requirement_repository.dart';
import '../../widgets/kpi_metric.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/single_column_grid.dart';
import 'requirement_create_panel.dart';
import 'requirement_detail_view.dart';
import 'requirement_module_dialog.dart';
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

  /// Rango de fechas de recepción. `null` = todas.
  ///
  /// Contra `receivedAt`, que es la fecha que muestra cada fila: filtrar por
  /// una fecha distinta de la que se ve es la receta para que alguien jure
  /// que el filtro está malo.
  DateTimeRange? _rango;
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
      if (_rango != null &&
          !inPeriod(r.receivedAt, _rango!.start, _rango!.end)) {
        return false;
      }
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
          rango: _rango,
          onRango: (v) => setState(() => _rango = v),
          vista: isMobile ? null : _vista,
          onVista: (v) => setState(() => _vista = v),
        );

        return LayoutBuilder(
          builder: (context, c) {
            // El panel de la derecha está siempre, como el "Nueva tarea" de
            // la Agenda diaria: sin clic previo, listo para escribir. Cuando
            // se abre un requerimiento muestra su detalle, y al cerrarlo
            // vuelve al formulario en vez de dejar el hueco vacío.
            final conPanel = c.maxWidth >= 1000;
            final columna = Column(
              children: [
                cabecera,
                Expanded(child: contenido),
              ],
            );
            if (!conPanel) {
              // Sin ancho para la columna de la derecha, el detalle flota
              // sobre la lista. Antes, por debajo de 1000 px, tocar un
              // requerimiento no hacía nada visible.
              //
              // El formulario de alta no flota: ahí no hay nada que leer
              // detrás y sigue teniendo su botón propio en la barra de
              // arriba, que lo abre como ventana.
              if (_seleccionado == null) return columna;
              return Stack(
                children: [
                  columna,
                  VentanaFlotante(
                    onClose: () => setState(() => _seleccionado = null),
                    child: RequirementDetailView(
                      key: ValueKey(_seleccionado),
                      requirementId: _seleccionado!,
                      onClose: () => setState(() => _seleccionado = null),
                    ),
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: columna),
                const VerticalDivider(width: 1),
                // Ancho fijo: con `Expanded` el formulario crecía con la
                // pantalla y en un monitor grande los campos quedaban
                // larguísimos, mientras la lista perdía sitio.
                SizedBox(
                  width: 420,
                  child: _seleccionado != null
                      ? RequirementDetailView(
                          key: ValueKey(_seleccionado),
                          requirementId: _seleccionado!,
                          onClose: () => setState(() => _seleccionado = null),
                        )
                      : const RequirementCreatePanel(enPanel: true),
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
    required this.rango,
    required this.onRango,
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
  final DateTimeRange? rango;
  final ValueChanged<DateTimeRange?> onRango;
  final _Vista? vista;
  final ValueChanged<_Vista> onVista;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Las cinco salen de un solo sitio y con pruebas: ver
    // `RequirementCounts`. Estaban sueltas aquí y una se desincronizó de su
    // propia etiqueta sin que nada lo notara.
    final cuentas = RequirementCounts.of(todos);

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

    // Los indicadores, con el nombre al lado de la cifra y no encima: así el
    // "15" nunca aparece huérfano. Michel vio la pantalla con el panel de la
    // derecha abierto, la tira se cortaba después de la primera tarjeta y
    // quedaba un 15 solo, sin forma de saber 15 de qué.
    //
    // Son los mismos bloques del Dashboard y de Reportes (`KpiMetric`), para
    // no tener una tercera manera de dibujar un indicador en la misma app.
    final metricas =
        <
          ({
            IconData icono,
            String nombre,
            String valor,
            Color color,
            String ayuda,
          })
        >[
          (
            icono: LucideIcons.inbox,
            nombre: 'Por aprobar',
            valor: '${cuentas.porAprobar}',
            color: Colors.blueGrey,
            ayuda: 'Recibidos que nadie ha aprobado ni rechazado todavía.',
          ),
          (
            icono: LucideIcons.lightbulb,
            nombre: 'Abiertos',
            valor: '${cuentas.abiertos}',
            color: colors.primary,
            ayuda:
                'Ni comunicados al cliente, ni en pausa, ni rechazados. Un '
                'publicado sigue abierto: falta avisarle al cliente.',
          ),
          (
            icono: LucideIcons.userX,
            nombre: 'Sin responsable',
            valor: '${cuentas.sinResponsable}',
            color: Colors.orange,
            ayuda: 'Abiertos sin desarrollador asignado.',
          ),
          (
            icono: LucideIcons.hammer,
            nombre: 'Desarrollo o QA',
            valor: '${cuentas.enDesarrolloOQa}',
            color: Colors.purple,
            ayuda: 'En desarrollo o en pruebas.',
          ),
          (
            icono: LucideIcons.megaphone,
            nombre: 'Por comunicar',
            valor: '${cuentas.porComunicar}',
            color: Colors.green,
            ayuda:
                'Ya publicados, pero al cliente todavía no se le ha avisado. '
                'Es el último paso y el que más se olvida.',
          ),
        ];

    final indicadores = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.divider),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          Widget bloque(int i) => Tooltip(
            message: metricas[i].ayuda,
            child: KpiMetric(
              icon: metricas[i].icono,
              title: metricas[i].nombre,
              value: metricas[i].valor,
              accentColor: metricas[i].color,
              dense: true,
            ),
          );

          // Cinco nombres con su icono al lado caben repartidos desde unos
          // 560 px. Por debajo se deslizan, como en Casos de Soporte.
          if (c.maxWidth >= 560) {
            return Row(
              children: [
                for (var i = 0; i < metricas.length; i++) ...[
                  if (i > 0)
                    Container(
                      width: 1,
                      height: 32,
                      color: colors.divider,
                      // 4 y no 8: son cuatro separadores, así que cada píxel
                      // que se les quita son 8 que gana el nombre más largo
                      // —"Sin responsable"— antes de cortarse.
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  Expanded(child: bloque(i)),
                ],
              ],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < metricas.length; i++) ...[
                  if (i > 0) const SizedBox(width: 14),
                  SizedBox(width: 108, child: bloque(i)),
                ],
              ],
            ),
          );
        },
      ),
    );

    // El selector con los dos nombres pide unos 175 px. A ventana angosta
    // ésos son justo los que le faltan al último indicador, que se quedaba
    // en "Por c" con la cifra tapada. Sin nombres son 95 y caben los cinco.
    // El nombre sigue estando al pasar el mouse.
    final anchoPantalla = MediaQuery.sizeOf(context).width;
    final conNombres = anchoPantalla >= 1250;
    final selector = vista == null
        ? null
        : SegmentedButton<_Vista>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _Vista.tabla,
                label: conNombres ? const Text('Lista') : null,
                tooltip: 'Lista',
                icon: const Icon(LucideIcons.list, size: 14),
              ),
              ButtonSegment(
                value: _Vista.tablero,
                label: conNombres ? const Text('Tablero') : null,
                tooltip: 'Tablero',
                icon: const Icon(LucideIcons.columns, size: 14),
              ),
            ],
            selected: {vista!},
            onSelectionChanged: (s) => onVista(s.first),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          );

    final campo = TextField(
      controller: buscador,
      style: TextStyle(color: colors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        hintText: 'Buscar cliente, texto, módulo o REQ-…',
        hintStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
        prefixIcon: Icon(LucideIcons.search, color: colors.primary, size: 16),
        prefixIconConstraints: const BoxConstraints(minWidth: 34),
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
        // Los de siempre más los que haya agregado el equipo: un filtro que
        // no ofrece un módulo que sí existe esconde requerimientos.
        context.watch<CatalogProvider>().requirementModules,
        onModulo,
        'Todos los módulos',
        conAgregar: true,
      ),
      _desplegable<String?>(
        context,
        valor: responsable,
        titulo: 'Responsable',
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
      ChipFecha(rango: rango, onChanged: onRango),
      FilterChip(
        label: const Text('Solo abiertos'),
        selected: soloAbiertos,
        onSelected: onSoloAbiertos,
        labelStyle: const TextStyle(fontSize: 12),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      ),
    ];

    // El conteo iba en su propia línea al final. Es una frase de doce
    // caracteres: cabe al lado de los filtros y ahorra una fila entera, que
    // es alto que le falta al tablero de abajo.
    final conteo = Text(
      '$mostrados de ${todos.length}',
      style: TextStyle(color: colors.textSecondary, fontSize: 12),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primera fila: los indicadores y, pegado a ellos, Lista/Tablero.
          // Antes el selector bajaba a una fila propia para él solo.
          Row(
            children: [
              Expanded(child: indicadores),
              if (selector != null) ...[const SizedBox(width: 8), selector],
            ],
          ),
          const SizedBox(height: 8),
          // Segunda fila: buscador, filtros y conteo. Eran tres filas.
          LayoutBuilder(
            builder: (context, c) {
              final angosto = c.maxWidth < 760;
              if (angosto) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    campo,
                    const SizedBox(height: 8),
                    _Tira(children: [...filtros, conteo]),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 250, child: campo),
                  const SizedBox(width: 10),
                  Expanded(
                    // Centrado: un `FilterChip` es más bajo que un
                    // desplegable, y sin esto se apoyaba en el borde de
                    // arriba y se veía desalineado.
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [...filtros, conteo],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _desplegable<T>(
    BuildContext context, {
    required T valor,
    required String titulo,
    required ValueChanged<T?> onChanged,
    required List<DropdownMenuItem<T>> items,
  }) {
    final colors = context.colors;
    return DropdownButton<T>(
      value: valor,
      underline: const SizedBox.shrink(),
      isDense: true,
      iconSize: 18,
      hint: Text(titulo, style: const TextStyle(fontSize: 13)),
      style: TextStyle(color: colors.textPrimary, fontSize: 13),
      onChanged: onChanged,
      items: items,
    );
  }

  Widget _filtro(
    BuildContext context,
    String titulo,
    String? valor,
    List<String> opciones,
    ValueChanged<String?> onChanged,
    String todos, {
    bool conAgregar = false,
  }) {
    return _desplegable<String?>(
      context,
      valor: opciones.contains(valor) ? valor : null,
      titulo: titulo,
      onChanged: (v) async {
        if (v != kAgregarModulo) {
          onChanged(v);
          return;
        }
        final creado = await pedirModuloNuevo(context);
        if (creado != null) onChanged(creado);
      },
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(todos)),
        for (final o in opciones)
          DropdownMenuItem<String?>(value: o, child: Text(o)),
        if (conAgregar) agregarModuloItem(context),
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
        // Antes de deslizar de lado, se quitan las columnas vacías.
        //
        // Siete columnas no caben en lo que deja el panel de la derecha, y el
        // tablero terminaba cortado por la mitad de "En QA" con el resto
        // fuera de la pantalla. Pero varias de esas columnas están vacías
        // precisamente por el filtro puesto: con "Solo abiertos", Publicado y
        // Comunicado al cliente no pueden tener nada nunca. Una columna vacía
        // que el filtro condena a estar vacía no informa de nada y se está
        // llevando el ancho que necesitan las que sí tienen tarjetas.
        //
        // Vuelven solas en cuanto algo entra en ese estado o se suelta el
        // filtro, si para entonces caben.
        const minimo = 170.0;
        double cabenEn(int n) => n * minimo + (n - 1) * 8;

        final util = c.maxWidth - 32;
        var visibles = columnas;
        if (util < cabenEn(columnas.length) &&
            util >= cabenEn(conItems.length)) {
          visibles = conItems;
        }
        final reparte = util >= cabenEn(visibles.length);

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
                for (var i = 0; i < visibles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: columna(visibles[i])),
                ],
              ],
            ),
          );
        }

        // Ni quitando las vacías caben: aquí sí se desliza, que es preferible
        // a columnas donde no cabe ni un nombre de cliente cortado.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < visibles.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                SizedBox(width: 260, child: columna(visibles[i])),
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
                    // Un poco de aire al final: sin esto la última tarjeta
                    // queda partida justo contra el borde de la columna y
                    // parece cortada en vez de parecer que falta deslizar.
                    padding: const EdgeInsets.only(bottom: 6),
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
