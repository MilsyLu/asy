import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/support_case_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/client_linking.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/support_case_metrics.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/support_case_model.dart';
import '../../models/support_case_tag_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/support_case_panel_provider.dart';
import 'support_cases_summary.dart';
import '../../services/catalog_repository.dart';
import '../../services/support_case_repository.dart';
import '../../widgets/calendario_menu.dart';
import '../../widgets/ventana_flotante.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/client_name_autocomplete.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_sheet.dart';
import '../../widgets/support_case_badges.dart';
import 'support_case_detail_view.dart';
import 'support_case_kanban_view.dart';
import 'support_case_tags_sheet.dart';

/// Valor del filtro de encargado que pide los casos sin asignar.
const String kSinEncargado = '__sin_encargado__';

/// Las vistas de la pantalla.
///
/// [resueltos] es una página aparte y no un filtro: los resueltos son 49 de
/// los 59 casos y ocupaban la columna más larga del tablero, empujando a las
/// demás. Lo que uno atiende a diario son los abiertos; lo resuelto se
/// consulta, no se trabaja. Así que la Tabla y el Kanban muestran sólo lo
/// abierto y lo resuelto tiene su propio botón.
enum _ViewMode { tabla, kanban, resumen, resueltos }

/// Los filtros rápidos que no son el estado.
///
/// Los cuatro que sí eran un estado —Pendientes, En seguimiento, Reportado,
/// Esperando cliente— salieron de aquí y son el desplegable "Estado". Eran
/// chips sólo en la Tabla: en el Kanban se escondían, porque elegir uno
/// vaciaba las otras tres columnas. Así que el estado se filtraba de una
/// forma en una vista y de ninguna en la otra. Ahora se filtra igual en las
/// dos, desde un solo sitio.
/// Los filtros rápidos que no son el estado.
///
/// "+10 días" estuvo aquí al lado de "+5 días" y sobraba: uno contiene al
/// otro —todo caso de más de 10 días lleva más de 5—, así que eran dos
/// botones que casi siempre mostraban el mismo número. Queda el de 5, que es
/// el que no deja escapar ninguno; para ver los peores de primeros está
/// ordenar por "Días sin resolver".
enum _QuickFilter { todos, altaPrioridad, mas5dias, misCasos }

extension on _QuickFilter {
  String get label {
    switch (this) {
      case _QuickFilter.todos:
        return 'Todos';
      case _QuickFilter.altaPrioridad:
        return 'Alta prioridad';
      // "+5 días" y no "Más de 5 días": dicen lo mismo y el corto deja
      // sitio en la fila.
      case _QuickFilter.mas5dias:
        return '+5 días';
      case _QuickFilter.misCasos:
        return 'Mis casos';
    }
  }

  bool matches(SupportCaseModel c, String? myUid) {
    switch (this) {
      case _QuickFilter.todos:
        return true;
      case _QuickFilter.altaPrioridad:
        return c.priority == SupportCasePriority.alta ||
            c.priority == SupportCasePriority.critica;
      case _QuickFilter.mas5dias:
        return SupportCaseStatus.isOpen(c.status) && c.daysOpen() > 5;
      case _QuickFilter.misCasos:
        return myUid != null &&
            (c.assignedUserId == myUid || c.createdBy == myUid);
    }
  }
}

enum _SortBy { recientes, antiguos, prioridad, dias }

const _priorityRank = {
  SupportCasePriority.critica: 3,
  SupportCasePriority.alta: 2,
  SupportCasePriority.media: 1,
  SupportCasePriority.baja: 0,
};

/// "Casos de Soporte" — a support-ticket tracker for VinApp's clients, open
/// to every signed-in user (create/read/comment/change status — see
/// firestore.rules; only permanent delete is gated). Table view only in v1
/// (Michel's own reference screenshot is a table too) — Kanban, tag
/// catalogs and automatic day-threshold push reminders are deferred.
/// Abre el formulario de caso nuevo.
///
/// Libre y no un método de la página porque los botones subieron a la barra
/// superior del shell, que no tiene acceso al estado de la pantalla. Ninguna
/// de las dos lo necesitaba: sólo abren una hoja.
void openSupportCaseCreateForm(BuildContext context) {
  showResponsiveSheet<void>(
    context,
    desktopMaxWidth: 480,
    contentBuilder: (sheetCtx) =>
        _NewCaseForm(onCreated: (_) => Navigator.of(sheetCtx).pop()),
  );
}

/// Abre la hoja de gestión de etiquetas. Ver [openSupportCaseCreateForm].
void openSupportCaseTagsSheet(BuildContext context) {
  showResponsiveSheet<void>(
    context,
    desktopMaxWidth: 420,
    contentBuilder: (_) => const SupportCaseTagsSheet(),
  );
}

class SupportCasesPage extends StatefulWidget {
  const SupportCasesPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<SupportCasesPage> createState() => _SupportCasesPageState();
}

class _SupportCasesPageState extends State<SupportCasesPage> {
  final _searchController = TextEditingController();
  String _query = '';
  _QuickFilter _filter = _QuickFilter.todos;

  /// Encargado por el que se filtra. `null` = todos.
  ///
  /// [kSinEncargado] es el centinela de "sin asignar": un `null` ahí
  /// significaría "no filtrar", así que los casos sin encargado necesitan un
  /// valor propio para poder pedirse.
  String? _assigneeFilter;

  /// Rango de fechas por el que se filtra. `null` = todas.
  ///
  /// Se compara contra `reportedAt`, que es la fecha que la lista muestra en
  /// cada fila. Filtrar por una fecha distinta de la que se ve sería la
  /// receta para que alguien jure que el filtro está malo.
  DateTimeRange? _rango;

  /// Estado por el que se filtra. `null` = todos.
  ///
  /// Guarda el valor tal como está en la base ("Nuevo", "En proceso"), no la
  /// etiqueta que se muestra: la etiqueta cambia cuando Michel quiere que
  /// cambie y el dato no tiene por qué enterarse.
  String? _statusFilter;
  String? _tagFilter;
  _SortBy _sortBy = _SortBy.recientes;
  _ViewMode _viewMode = _ViewMode.tabla;

  // El periodo del Resumen vive aquí y no dentro de él para que sobreviva a
  // cambiar de vista: elegir "Últimos 7 días", pasar a la Tabla y volver no
  // debería devolverlo a su valor por defecto.
  PeriodoResumen _periodo = PeriodoResumen.preset(
    PeriodoResumen.indicePorDefecto,
  );

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SupportCaseModel> _applyFiltersAndSort(
    List<SupportCaseModel> all,
    String? myUid,
    String Function(String?) nombreDe,
  ) {
    final q = _query.trim().toLowerCase();
    var result = all.where((c) => _filter.matches(c, myUid)).toList();
    if (_tagFilter != null) {
      result = result.where((c) => c.tags.contains(_tagFilter)).toList();
    }
    if (_statusFilter != null) {
      result = result.where((c) => c.status == _statusFilter).toList();
    }
    if (_rango != null) {
      result = result
          .where((c) => inPeriod(c.reportedAt, _rango!.start, _rango!.end))
          .toList();
    }
    if (_assigneeFilter != null) {
      result = result.where((c) {
        final sinAsignar =
            c.assignedUserId == null || c.assignedUserId!.isEmpty;
        return _assigneeFilter == kSinEncargado
            ? sinAsignar
            : c.assignedUserId == _assigneeFilter;
      }).toList();
    }
    if (q.isNotEmpty) {
      result = result.where((c) {
        return c.clientName.toLowerCase().contains(q) ||
            c.contactName.toLowerCase().contains(q) ||
            c.subject.toLowerCase().contains(q) ||
            c.description.toLowerCase().contains(q) ||
            c.status.toLowerCase().contains(q) ||
            // El encargado también: escribir "natalia" en el buscador es lo
            // primero que uno intenta, y antes no devolvía nada.
            nombreDe(c.assignedUserId).toLowerCase().contains(q) ||
            c.tags.any((t) => t.toLowerCase().contains(q)) ||
            'cs-${c.caseNumber.toString().padLeft(4, '0')}'.contains(q);
      }).toList();
    }
    switch (_sortBy) {
      case _SortBy.recientes:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case _SortBy.antiguos:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case _SortBy.prioridad:
        result.sort(
          (a, b) => (_priorityRank[b.priority] ?? -1).compareTo(
            _priorityRank[a.priority] ?? -1,
          ),
        );
        break;
      case _SortBy.dias:
        result.sort((a, b) => b.daysOpen().compareTo(a.daysOpen()));
        break;
    }
    return result;
  }

  void _openCreateForm(BuildContext context) =>
      openSupportCaseCreateForm(context);

  void _openManageTags(BuildContext context) =>
      openSupportCaseTagsSheet(context);

  void _openDetail(BuildContext context, String caseId) {
    if (context.isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              SupportCaseDetailView(caseId: caseId, showAppBar: true),
        ),
      );
    } else {
      context.read<SupportCasePanelController>().openCase(caseId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SupportCaseRepository>();
    // Para el desplegable de encargado y para que el buscador reconozca un
    // nombre de persona, no sólo de cliente.
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final myUid = auth.appUser?.id;
    final isMobile = context.isMobile;
    final panel = context.watch<SupportCasePanelController>();

    final fab = isMobile
        ? FloatingActionButton(
            onPressed: () => _openCreateForm(context),
            child: const Icon(LucideIcons.plus),
          )
        : null;

    final body = StreamBuilder<List<SupportCaseModel>>(
      stream: repo.watchAll(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LoadingIndicator();
        final all = snapshot.data!;
        final filtered = _applyFiltersAndSort(all, myUid, catalog.userName);

        final canDelete = auth.hasPermission(AppPermissions.manageSupportCases);

        // Cada vista recibe lo que le toca. El Resumen necesita los resueltos
        // —sin ellos no hay tiempo de resolución ni salidas que graficar—,
        // así que es la única que los ve junto a los abiertos.
        final abiertos = filtered
            .where((c) => SupportCaseStatus.isOpen(c.status))
            .toList();
        final resueltos = filtered
            .where((c) => !SupportCaseStatus.isOpen(c.status))
            .toList();
        // El Resumen recibe los casos ya filtrados, igual que la tabla y el
        // tablero: un filtro cambia las tres vistas de la misma forma.
        final list = (!isMobile && _viewMode == _ViewMode.resumen)
            ? SupportCasesSummary(
                cases: filtered,
                periodo: _periodo,
                onPeriodoChanged: (p) => setState(() => _periodo = p),
              )
            : (!isMobile && _viewMode == _ViewMode.kanban)
            ? SupportCaseKanbanView(
                cases: abiertos,
                onTap: (id) => _openDetail(context, id),
              )
            : _CaseList(
                // Lo resuelto sólo aparece si se pide: por el botón
                // Resueltos o eligiéndolo en el filtro de estado, que es la
                // única forma de llegar a ellos desde un teléfono —ahí no
                // hay botón de vistas—.
                cases:
                    (_viewMode == _ViewMode.resueltos ||
                        _statusFilter == SupportCaseStatus.resuelto)
                    ? resueltos
                    : abiertos,
                selectedCaseId: panel.caseId,
                onTap: (id) => _openDetail(context, id),
                canDelete: canDelete,
              );

        final header = _CasesHeader(
          all: all,
          searchController: _searchController,
          onQueryChanged: (v) => setState(() => _query = v),
          filter: _filter,
          onFilterChanged: (f) => setState(() => _filter = f),
          tagFilter: _tagFilter,
          onTagFilterChanged: (t) => setState(() => _tagFilter = t),
          assigneeFilter: _assigneeFilter,
          onAssigneeFilterChanged: (v) => setState(() => _assigneeFilter = v),
          // En Resueltos no se ofrece: todos tienen el mismo estado y el
          // desplegable sólo podría dejar la pantalla en blanco.
          statusFilter: _viewMode == _ViewMode.resueltos ? null : _statusFilter,
          onStatusFilterChanged: (v) => setState(() => _statusFilter = v),
          rango: _rango,
          onRangoChanged: (v) => setState(() => _rango = v),
          mostrarEstados: isMobile || _viewMode != _ViewMode.resueltos,
          myUid: myUid,
          sortBy: _sortBy,
          onSortChanged: (s) => setState(() => _sortBy = s),
          // Sólo en celular: en escritorio ambos viven en la barra superior
          // (ver _supportCaseActions en main_shell.dart). En celular esa barra
          // no lleva acciones por sección y crear un caso ya tiene su botón
          // flotante, así que aquí sólo queda gestionar etiquetas.
          onManageTags: (canDelete && isMobile)
              ? () => _openManageTags(context)
              : null,
          viewMode: isMobile ? null : _viewMode,
          onViewModeChanged: (v) => setState(() {
            _viewMode = v;
            // En Resueltos un estado abierto no dejaría pasar nada, y el
            // desplegable ni siquiera se muestra: sería un filtro invisible
            // escondiendo casos. Se suelta.
            if (v == _ViewMode.resueltos) _statusFilter = null;
          }),
        );

        if (isMobile) {
          return Column(
            children: [
              header,
              Expanded(child: list),
            ],
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // En Resumen no se abre el panel para *leer* un caso: dejaría
            // la gráfica en un tercio de pantalla, que es donde deja de
            // leerse. Crear uno sí lo abre — bloquearlo también dejaba el
            // botón "Nuevo caso" sin hacer absolutamente nada desde esta
            // vista, que es peor que una gráfica estrecha un rato.
            // ¿Hay detalle que mostrar? Es una sola pregunta; el ancho
            // decide sólo *dónde* se muestra, no *si* se muestra. Antes el
            // ancho decidía las dos cosas a la vez, y por debajo de 900 el
            // clic en un caso no hacía nada visible: se abría un panel que
            // nadie dibujaba.
            final hayDetalle =
                panel.isOpen &&
                (panel.creating || _viewMode != _ViewMode.resumen);
            final sideBySide = constraints.maxWidth >= 900 && hayDetalle;
            final listColumn = Column(
              children: [
                header,
                Expanded(child: list),
              ],
            );
            final contenidoPanel = panel.creating
                ? _NewCasePanel(
                    onCreated: (nuevoId) => context
                        .read<SupportCasePanelController>()
                        .openCase(nuevoId),
                    onClose: () =>
                        context.read<SupportCasePanelController>().close(),
                  )
                : SupportCaseDetailView(
                    key: ValueKey(panel.caseId),
                    caseId: panel.caseId ?? '',
                    showAppBar: false,
                    onClose: () =>
                        context.read<SupportCasePanelController>().close(),
                  );

            if (!sideBySide) {
              // Sin ancho para la columna, el detalle flota sobre la lista.
              return Stack(
                children: [
                  listColumn,
                  if (hayDetalle)
                    VentanaFlotante(
                      onClose: () =>
                          context.read<SupportCasePanelController>().close(),
                      child: contenidoPanel,
                    ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: listColumn),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  // El mismo espacio sirve para leer un caso y para crear uno.
                  // El formulario estaba en una ventana emergente que tapaba la
                  // lista; aqui se ve al lado de los casos que ya existen, que
                  // es justo lo que uno mira mientras registra uno nuevo.
                  child: contenidoPanel,
                ),
              ],
            );
          },
        );
      },
    );

    if (!widget.showAppBar) {
      return Scaffold(body: body, floatingActionButton: fab);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Casos de Soporte')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

// ---------------------------------------------------------------------------
// Header: KPIs + search + quick filters + sort + "Nuevo caso"
// ---------------------------------------------------------------------------

class _CasesHeader extends StatelessWidget {
  const _CasesHeader({
    required this.all,
    required this.searchController,
    required this.onQueryChanged,
    required this.filter,
    required this.onFilterChanged,
    required this.tagFilter,
    required this.onTagFilterChanged,
    required this.assigneeFilter,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.rango,
    required this.onRangoChanged,
    required this.mostrarEstados,
    required this.myUid,
    required this.onAssigneeFilterChanged,
    required this.sortBy,
    required this.onSortChanged,
    required this.onManageTags,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final List<SupportCaseModel> all;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final _QuickFilter filter;
  final ValueChanged<_QuickFilter> onFilterChanged;

  /// Null = "todas las etiquetas". Options are derived from whatever tags
  /// are actually applied to at least one case in [all] — no separate
  /// Firestore read needed here, and it never offers a tag with zero
  /// matching cases.
  final String? tagFilter;
  final ValueChanged<String?> onTagFilterChanged;

  /// Null = todos los encargados; [kSinEncargado] = sólo los sin asignar.
  final String? assigneeFilter;
  final String? statusFilter;
  final ValueChanged<String?> onStatusFilterChanged;
  final DateTimeRange? rango;
  final ValueChanged<DateTimeRange?> onRangoChanged;
  final bool mostrarEstados;

  /// Para contar los casos de quien está mirando.
  final String? myUid;
  final ValueChanged<String?> onAssigneeFilterChanged;

  final _SortBy sortBy;
  final ValueChanged<_SortBy> onSortChanged;

  /// Null when the viewer lacks `manageSupportCases` — hides the button.
  final VoidCallback? onManageTags;

  /// Null on mobile — hides the Tabla/Kanban toggle (Kanban's 5 columns
  /// don't fit a phone screen).
  final _ViewMode? viewMode;
  final ValueChanged<_ViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final availableTags = all.expand((c) => c.tags).toSet().toList()..sort();

    // (id, nombre, cuántos casos). El conteo va en la opción para que se vea
    // de una vez cuánto carga cada quien, sin tener que elegir y contar.
    final porEncargado = <String, int>{};
    for (final c in all) {
      final id = (c.assignedUserId == null || c.assignedUserId!.isEmpty)
          ? kSinEncargado
          : c.assignedUserId!;
      porEncargado[id] = (porEncargado[id] ?? 0) + 1;
    }
    final catalogo = context.watch<CatalogProvider>();
    final encargados =
        porEncargado.entries
            .map(
              (e) => (
                e.key,
                e.key == kSinEncargado
                    ? 'Sin encargado'
                    : catalogo.userName(e.key),
                e.value,
              ),
            )
            .toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));
    // Las cinco tarjetas de indicadores que había aquí —Casos abiertos,
    // Urgentes, Más de 5 días, Más de 10 días, Resueltos hoy— se fueron a los
    // filtros de abajo, que ya decían tres de las cinco cosas con otras
    // palabras: "Alta prioridad" era Urgentes, "+5 días" era Más de 5 días,
    // "+10 días" era Más de 10 días. La cifra ahora está en el botón que la
    // filtra, que es donde uno va a parar después de leerla, y la pantalla se
    // ahorró una fila entera: con el filtro de estado nuevo, las tarjetas se
    // quedaban en "Ca…", "Ur…" con la cifra tapada.
    //
    // "Resueltos hoy" vive en el Resumen, donde además se puede pedir el
    // periodo que uno quiera en vez de sólo hoy.
    final base = viewMode == _ViewMode.resueltos
        ? all.where((c) => !SupportCaseStatus.isOpen(c.status)).toList()
        : all.where((c) => SupportCaseStatus.isOpen(c.status)).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En escritorio no hay fila de título ni botones: el nombre de la
          // pantalla y las acciones viven en la barra superior, que cruzaba el
          // ancho entero sin usar. En celular esa barra no lleva acciones por
          // sección, así que el botón de etiquetas se queda aquí.
          if (onManageTags != null)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Gestionar etiquetas',
                onPressed: onManageTags,
                icon: Icon(LucideIcons.tag, color: colors.primary, size: 20),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final angosto = constraints.maxWidth < 640;

              // Buscador y controles comparten fila sólo si sobra ancho de
              // verdad: los cuatro desplegables más el selector de vista
              // piden unos 900 px que no ceden. Por debajo, los controles se
              // llevan su propia tira deslizable.
              final holgado = constraints.maxWidth >= 1200;

              final buscador = TextField(
                controller: searchController,
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar caso, cliente o número',
                  prefixIcon: Icon(
                    LucideIcons.search,
                    color: colors.primary,
                    size: 18,
                  ),
                ),
                onChanged: onQueryChanged,
              );

              final controles = <Widget>[
                DropdownButton<_SortBy>(
                  value: sortBy,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  iconSize: 18,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  onChanged: (v) => v != null ? onSortChanged(v) : null,
                  items: const [
                    DropdownMenuItem(
                      value: _SortBy.recientes,
                      child: Text('Más recientes'),
                    ),
                    DropdownMenuItem(
                      value: _SortBy.antiguos,
                      child: Text('Más antiguos'),
                    ),
                    DropdownMenuItem(
                      value: _SortBy.prioridad,
                      child: Text('Prioridad'),
                    ),
                    DropdownMenuItem(
                      value: _SortBy.dias,
                      child: Text('Días sin resolver'),
                    ),
                  ],
                ),
                // Estado. Con la cuenta al lado, que es la mitad de la
                // pregunta: cuántos hay esperando al cliente se responde sin
                // elegir nada.
                if (mostrarEstados)
                  DropdownButton<String?>(
                    value: statusFilter,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    iconSize: 18,
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    hint: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.circleDot,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        const Text('Estado'),
                      ],
                    ),
                    onChanged: onStatusFilterChanged,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos los estados'),
                      ),
                      // En escritorio los resueltos tienen su propio botón,
                      // así que ofrecerlos aquí sería la misma cosa dos
                      // veces. En celular no hay botón de vistas: este
                      // filtro es el único camino.
                      for (final e
                          in viewMode == null
                              ? SupportCaseStatus.all
                              : SupportCaseStatus.openStates)
                        DropdownMenuItem<String?>(
                          value: e,
                          child: Text(
                            '${SupportCaseStatus.columnLabelFor(e)} '
                            '(${all.where((c) => c.status == e).length})',
                          ),
                        ),
                    ],
                  ),
                // Encargado. Sólo se ofrecen las personas que de verdad
                // tienen algún caso: una lista con los seis usuarios de la
                // empresa haría elegir entre nombres que no devuelven nada.
                if (encargados.isNotEmpty)
                  DropdownButton<String?>(
                    value: assigneeFilter,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    iconSize: 18,
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    hint: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.userCheck,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        const Text('Encargado'),
                      ],
                    ),
                    onChanged: onAssigneeFilterChanged,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todos los encargados'),
                      ),
                      for (final e in encargados)
                        DropdownMenuItem<String?>(
                          value: e.$1,
                          child: Text('${e.$2} (${e.$3})'),
                        ),
                    ],
                  ),
                if (availableTags.isNotEmpty)
                  DropdownButton<String?>(
                    value: tagFilter,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    iconSize: 18,
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    hint: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.tag,
                          size: 14,
                          color: colors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        const Text('Etiqueta'),
                      ],
                    ),
                    onChanged: onTagFilterChanged,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todas las etiquetas'),
                      ),
                      for (final tag in availableTags)
                        DropdownMenuItem<String?>(value: tag, child: Text(tag)),
                    ],
                  ),
              ];

              // El selector de vista, aparte de los desplegables: en ventana
              // angosta va al lado del buscador en vez de llevarse una fila
              // para él solo con medio ancho en blanco a su derecha.
              final Widget? selectorVista = viewMode == null
                  ? null
                  : SegmentedButton<_ViewMode>(
                      // Sin la marca de "elegido" a la izquierda del nombre:
                      // son cuatro vistas y ese palomito corría cada etiqueta
                      // unos 20 px, que al final eran 80 de fila. El segmento
                      // elegido ya se distingue por el color.
                      showSelectedIcon: false,
                      // En ventana angosta, sólo los iconos. Con nombre, los
                      // cuatro segmentos piden unos 430 px: sumados a los
                      // cuatro desplegables no caben, y la fila terminaba
                      // partiendo el selector contra el borde derecho. Sin
                      // nombre son 180 y caben todos. El nombre sigue estando
                      // al pasar el mouse.
                      segments: [
                        ButtonSegment(
                          value: _ViewMode.tabla,
                          label: holgado ? const Text('Tabla') : null,
                          tooltip: 'Tabla',
                          icon: const Icon(LucideIcons.list, size: 14),
                        ),
                        ButtonSegment(
                          value: _ViewMode.kanban,
                          label: holgado ? const Text('Kanban') : null,
                          tooltip: 'Kanban',
                          icon: const Icon(LucideIcons.columns, size: 14),
                        ),
                        ButtonSegment(
                          value: _ViewMode.resumen,
                          label: holgado ? const Text('Resumen') : null,
                          tooltip: 'Resumen',
                          icon: const Icon(LucideIcons.barChart2, size: 14),
                        ),
                        ButtonSegment(
                          value: _ViewMode.resueltos,
                          label: holgado ? const Text('Resueltos') : null,
                          tooltip: 'Resueltos',
                          icon: const Icon(LucideIcons.checkCircle2, size: 14),
                        ),
                      ],
                      selected: {viewMode!},
                      onSelectionChanged: (s) => onViewModeChanged(s.first),
                      style: const ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(fontSize: 12.5),
                        ),
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    );

              final chips = <Widget>[
                for (final f in _QuickFilter.values)
                  _FilterChip(
                    label: f.label,
                    cantidad: base.where((c) => f.matches(c, myUid)).length,
                    selected: filter == f,
                    onTap: () => onFilterChanged(f),
                  ),
                ChipFecha(rango: rango, onChanged: onRangoChanged),
              ];

              if (angosto) {
                // En un teléfono no hay ancho que repartir: cada grupo se lleva
                // su propia tira, y la que no cabe se desliza de lado en vez de
                // apilarse y comerse media pantalla antes del primer caso.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TiraHorizontal(children: controles),
                    const SizedBox(height: 8),
                    buscador,
                    const SizedBox(height: 8),
                    _TiraHorizontal(children: chips),
                    if (selectorVista != null) ...[
                      const SizedBox(height: 8),
                      _TiraHorizontal(children: [selectorVista]),
                    ],
                  ],
                );
              }

              if (!holgado) {
                // Ancho intermedio —el panel del detalle abierto, o la ventana
                // a media pantalla—. Los controles se deslizan de lado si no
                // caben, que es preferible a verlos aplastados.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // `Wrap` y no una tira deslizable: deslizándose, el
                    // último control quedaba partido contra el borde y
                    // parecía roto. Bajando de línea se ve entero.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: controles,
                    ),
                    const SizedBox(height: 8),
                    // El buscador se estira y el selector de vista se le
                    // pega a la derecha. Antes el selector tenía una fila
                    // propia con medio ancho en blanco al lado, y el
                    // buscador otra media fila vacía debajo.
                    Row(
                      children: [
                        Expanded(child: buscador),
                        if (selectorVista != null) ...[
                          const SizedBox(width: 10),
                          selectorVista,
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Los filtros, a todo el ancho: con la fila entera para
                    // ellos caben los cinco en una línea en vez de dejar
                    // "Mis casos" solo abajo.
                    Wrap(spacing: 8, runSpacing: 8, children: chips),
                  ],
                );
              }

              // Escritorio holgado: dos filas, y la segunda sólo si hace
              // falta. Antes eran tres —indicadores, controles, filtros— y la
              // primera se iba casi entera en cinco tarjetas que decían lo
              // mismo que los filtros de la tercera.
              return Column(
                children: [
                  Row(
                    children: [
                      // Ancho fijo: los controles conservan su tamaño y el
                      // espacio lo cede el buscador, que es de donde sobra.
                      SizedBox(width: 250, child: buscador),
                      const SizedBox(width: 12),
                      // `Wrap` y no una fila: si algún día no caben —una
                      // etiqueta de nombre largo, una ventana angosta— bajan
                      // de línea y se ven enteros, en vez de que el último
                      // quede cortado contra el borde. Con los tamaños de
                      // ahora caben los cinco en una sola línea, que es como
                      // Michel lo quiere: dos filas arriba, no tres.
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [...controles, ?selectorVista],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // `Wrap` y no una tira deslizable: si no caben, bajan de
                  // línea y se ven todos, en vez de que el último quede
                  // cortado contra el borde sin nada que lo indique.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, runSpacing: 8, children: chips),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.cantidad,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Cuántos casos deja pasar este filtro ahora mismo.
  ///
  /// Es la cifra que antes estaba en una tarjeta de indicador aparte. Aquí
  /// responde la pregunta y además dice qué va a pasar si uno lo toca.
  final int? cantidad;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? colors.primary : colors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? colors.onPrimary : colors.textSecondary,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (cantidad != null) ...[
              const SizedBox(width: 6),
              Text(
                '$cantidad',
                style: TextStyle(
                  color: selected ? colors.onPrimary : colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

/// Shared by the table row and (in the future, if needed) any other quick
/// delete entry point — same confirm+delete flow the detail view already
/// has, just reachable without opening it first.
/// Devuelve si el caso quedó realmente eliminado — el gesto de deslizar lo
/// necesita para decidir si la fila desaparece o vuelve a su sitio: si el
/// usuario cancela, o si el borrado falla, la fila tiene que seguir ahí.
Future<bool> confirmDeleteSupportCase(
  BuildContext context,
  SupportCaseModel c,
) async {
  final confirm = await showConfirmDialog(
    context,
    title: 'Eliminar caso',
    message:
        '¿Eliminar el caso CS-${c.caseNumber.toString().padLeft(4, '0')} '
        '(${c.clientName}) de forma permanente? Esta acción no se puede deshacer.',
    confirmLabel: 'Eliminar',
    destructive: true,
  );
  if (!confirm || !context.mounted) return false;
  try {
    await context.read<SupportCaseRepository>().delete(c.id);
    if (context.mounted) SnackbarUtils.showSuccess(context, 'Caso eliminado');
    return true;
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
    return false;
  }
}

class _CaseList extends StatelessWidget {
  const _CaseList({
    required this.cases,
    required this.selectedCaseId,
    required this.onTap,
    required this.canDelete,
  });

  final List<SupportCaseModel> cases;
  final String? selectedCaseId;
  final void Function(String caseId) onTap;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    if (cases.isEmpty) {
      return const EmptyState(
        message: 'No hay casos que coincidan con la búsqueda/filtro.',
        icon: LucideIcons.inbox,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: cases.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final c = cases[index];
        final angosto = context.isMobile;
        final fila = _CaseRow(
          caseModel: c,
          selected: c.id == selectedCaseId,
          onTap: () => onTap(c.id),
          // El bote de basura sólo en pantalla ancha. En un teléfono, con
          // filas de dedo y sin "deshacer" detrás, un toque errado borra un
          // caso — y el icono estaba pegado a la insignia de días, que es
          // justo donde cae la vista.
          onDelete: (canDelete && !angosto)
              ? () => confirmDeleteSupportCase(context, c)
              : null,
        );

        if (!angosto || !canDelete) return fila;

        // Deslizar para eliminar: el gesto que ya se espera en una lista de
        // teléfono, y que además pide confirmación antes de hacer nada. No
        // queda como única vía — el detalle del caso sigue teniendo su propio
        // botón de eliminar, que es donde alguien que no conozca el gesto va a
        // buscarlo.
        return Dismissible(
          key: ValueKey(c.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => confirmDeleteSupportCase(context, c),
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: context.colors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Icon(LucideIcons.trash2, color: context.colors.error),
          ),
          child: fila,
        );
      },
    );
  }
}

Color _avatarColorFor(String name) {
  if (name.isEmpty) return Colors.grey;
  return Colors.primaries[name.hashCode.abs() % Colors.primaries.length];
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

/// Una fila de widgets que se desliza de lado en vez de envolverse o salirse.
///
/// La usan los indicadores, los desplegables y los filtros rápidos: en los tres
/// el problema era el mismo — en pantalla angosta se apilaban o se salían por
/// el borde, y en el segundo caso ni siquiera se alcanzaba a ver que faltaba
/// algo.
class _TiraHorizontal extends StatelessWidget {
  const _TiraHorizontal({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // Sin recorte, lo que no cabe no se corta: se pinta encima del vecino.
      // Una tarjeta a medias avisa de que la tira se desliza; una tarjeta
      // montada sobre el desplegable de al lado parece un error, y lo era.
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

class _CaseRow extends StatelessWidget {
  const _CaseRow({
    required this.caseModel,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final SupportCaseModel caseModel;
  final bool selected;
  final VoidCallback onTap;

  /// Null when the viewer lacks `manageSupportCases` — hides the icon.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final c = caseModel;
    final avatarColor = _avatarColorFor(c.clientName);
    final priorityColor = SupportCasePriority.colorFor(c.priority);
    final isResolved = !SupportCaseStatus.isOpen(c.status);
    final formattedDate = AppDateUtils.formatShortDate(c.reportedAt);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.07)
              : colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: selected ? colors.primary : colors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Debajo de esto la fila de una sola línea deja de funcionar, y no
            // por poco: las insignias piden un ancho fijo de unos 250 px entre
            // todas, mientras el cliente y el asunto viven en un `Expanded` que
            // se lleva lo que sobre. En un teléfono no sobra nada, así que lo
            // único que la pantalla sacrificaba era justo lo que hace falta
            // para saber de qué caso se trata.
            final apilado = constraints.maxWidth < 560;
            final showContact = constraints.maxWidth >= 520;
            final showDate = constraints.maxWidth >= 720;

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: priorityColor,
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(10),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: apilado
                          ? _apilada(context, c, avatarColor, isResolved)
                          : _enLinea(
                              context,
                              c,
                              avatarColor,
                              isResolved,
                              formattedDate,
                              showContact: showContact,
                              showDate: showDate,
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Diseño angosto: tres renglones en vez de una línea.
  ///
  /// El cliente y el asunto ocupan el ancho completo, los días quedan a la
  /// derecha del primer renglón —es lo que se escanea— y las insignias bajan a
  /// su propio renglón, donde no le quitan espacio a nada.
  Widget _apilada(
    BuildContext context,
    SupportCaseModel c,
    Color avatarColor,
    bool isResolved,
  ) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatar(avatarColor, c.clientName),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'CS-${c.caseNumber.toString().padLeft(4, '0')} · ${c.clientName}',
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
                  DaysOpenBadge(
                    days: c.daysOpen(),
                    resolved: isResolved,
                    dense: true,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                c.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              if (c.contactName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  c.contactName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusBadge(status: c.status, dense: true),
                  PriorityBadge(priority: c.priority, dense: true),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Diseño ancho: la línea única de siempre, sin cambios de fondo.
  Widget _enLinea(
    BuildContext context,
    SupportCaseModel c,
    Color avatarColor,
    bool isResolved,
    String formattedDate, {
    required bool showContact,
    required bool showDate,
  }) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _avatar(avatarColor, c.clientName),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CS-${c.caseNumber.toString().padLeft(4, '0')} · ${c.clientName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                c.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              if (showContact && c.contactName.isNotEmpty)
                Text(
                  c.contactName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        StatusBadge(status: c.status, dense: true),
        const SizedBox(width: 6),
        PriorityBadge(priority: c.priority, dense: true),
        if (showDate) ...[
          const SizedBox(width: 10),
          Text(
            formattedDate,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
        const SizedBox(width: 10),
        DaysOpenBadge(days: c.daysOpen(), resolved: isResolved, dense: true),
        if (onDelete != null)
          IconButton(
            tooltip: 'Eliminar',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.trash2, color: colors.error),
            onPressed: onDelete,
          ),
      ],
    );
  }

  Widget _avatar(Color color, String name) => CircleAvatar(
    radius: 18,
    backgroundColor: color.withValues(alpha: 0.85),
    child: Text(
      _initialsFor(name),
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Create form
// ---------------------------------------------------------------------------

/// El formulario de caso nuevo, montado en el panel derecho.
///
/// Sólo agrega el encabezado con el botón de cerrar y el desplazamiento; el
/// formulario en sí es el mismo que usa la hoja en celular, para que no haya
/// dos versiones que mantener a la par.
class _NewCasePanel extends StatelessWidget {
  const _NewCasePanel({required this.onCreated, required this.onClose});

  final ValueChanged<String> onCreated;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Icon(LucideIcons.plus, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Nuevo caso',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: onClose,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: _NewCaseForm(onCreated: onCreated, showTitle: false),
          ),
        ),
      ],
    );
  }
}

class _NewCaseForm extends StatefulWidget {
  const _NewCaseForm({required this.onCreated, this.showTitle = true});

  /// Recibe el id del caso recién creado, para que quien lo montó decida qué
  /// hacer: la hoja de celular se cierra, el panel abre el caso nuevo.
  final ValueChanged<String> onCreated;

  /// El panel ya pone su propio encabezado con el botón de cerrar.
  final bool showTitle;

  @override
  State<_NewCaseForm> createState() => _NewCaseFormState();
}

class _NewCaseFormState extends State<_NewCaseForm> {
  final _formKey = GlobalKey<FormState>();
  final _clientController = TextEditingController();
  final _contactController = TextEditingController();
  final _phoneController = TextEditingController();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _priority = SupportCasePriority.media;
  String? _assignedUserId;
  DateTime _reportedAt = DateTime.now();
  final Set<String> _selectedTags = {};
  bool _isSaving = false;

  /// Cliente enlazado cuando se eligió uno de las sugerencias.
  ///
  /// Se limpia si después se edita el nombre a mano, para que el caso no
  /// afirme estar enlazado a un cliente cuyo nombre ya no coincide con lo
  /// escrito — al guardar se resuelve o se crea desde el texto final.
  String? _clientId;
  String? _linkedClientName;
  final _clientFocusNode = FocusNode();

  /// Recordatorio opcional, programado en el mismo formulario.
  ///
  /// Antes habia que crear el caso, abrirlo y programarlo desde el detalle:
  /// tres pasos para algo que casi siempre se decide al registrar el caso.
  DateTime? _reminderAt;
  final _reminderNoteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _clientController.addListener(_onClientNameChanged);
  }

  void _onClientNameChanged() {
    if (_clientId == null) return;
    if (_clientController.text != _linkedClientName) {
      setState(() {
        _clientId = null;
        _linkedClientName = null;
      });
    }
  }

  Future<void> _pickReminder() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _reminderAt ?? ahora.add(const Duration(days: 1)),
      firstDate: ahora,
      lastDate: ahora.add(const Duration(days: 365 * 2)),
      helpText: 'Fecha del recordatorio',
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _reminderAt ?? ahora.add(const Duration(hours: 1)),
      ),
      helpText: 'Hora del recordatorio',
    );
    if (hora == null || !mounted) return;

    setState(() {
      _reminderAt = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );
    });
  }

  @override
  void dispose() {
    _clientController.removeListener(_onClientNameChanged);
    _clientFocusNode.dispose();
    _reminderNoteController.dispose();
    _clientController.dispose();
    _contactController.dispose();
    _phoneController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickReportedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _reportedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Fecha en que se reportó el caso',
    );
    if (picked != null) setState(() => _reportedAt = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final user = auth.appUser;
    if (user == null) return;
    final repo = context.read<SupportCaseRepository>();
    final catalog = context.read<CatalogProvider>();
    final catalogRepo = context.read<CatalogRepository>();
    setState(() => _isSaving = true);
    try {
      // Esto es lo que hace que la lista de Clientes se llene sola desde los
      // casos, como ya pasaba con las tareas. Antes un caso guardaba el nombre
      // del cliente como texto suelto y ahi moria.
      final clientId = await ClientLinking.forSupportCase(
        catalog: catalog,
        repository: catalogRepo,
        linkedId: _clientId,
        clientName: _clientController.text,
        contactPhone: _phoneController.text,
      );

      final caseId = await repo.createCase(
        clientName: _clientController.text.trim(),
        clientId: clientId,
        contactName: _contactController.text.trim(),
        contactPhone: _phoneController.text.trim(),
        subject: _subjectController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _priority,
        tags: _selectedTags.toList(),
        assignedUserId: _assignedUserId,
        reportedAt: _reportedAt,
        createdBy: user.id,
        createdByName: user.name,
      );

      if (_reminderAt != null) {
        await repo.setReminder(
          caseId,
          reminderTime: _reminderAt,
          reminderNote: _reminderNoteController.text.trim(),
          authorId: user.id,
          authorName: user.name,
        );
      }

      if (mounted) {
        SnackbarUtils.showSuccess(context, 'Caso creado');
        widget.onCreated(caseId);
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showTitle)
                Text(
                  'Nuevo caso',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              const SizedBox(height: 16),
              ClientNameAutocomplete(
                clients: catalog.clients,
                controller: _clientController,
                focusNode: _clientFocusNode,
                label: 'Cliente *',
                onSelected: (c) => setState(() {
                  _clientId = c.id;
                  _linkedClientName = c.name;
                }),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'El cliente es obligatorio'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactController,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Persona que reportó (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectController,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(labelText: 'Asunto *'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'El asunto es obligatorio'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _priority,
                      decoration: const InputDecoration(labelText: 'Prioridad'),
                      items: [
                        for (final p in SupportCasePriority.all)
                          DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) =>
                          setState(() => _priority = v ?? _priority),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _pickReportedDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de reporte',
                        ),
                        child: Text(
                          AppDateUtils.formatShortDate(_reportedAt),
                          style: TextStyle(color: colors.textPrimary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Recordatorio, aqui mismo. Antes habia que crear el caso,
              // abrirlo y programarlo desde el detalle: tres pasos para algo
              // que casi siempre se decide al registrar el caso.
              InkWell(
                onTap: _pickReminder,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Recordarme (opcional)',
                    prefixIcon: Icon(LucideIcons.bell, color: colors.primary),
                    suffixIcon: _reminderAt == null
                        ? const Icon(LucideIcons.chevronRight, size: 18)
                        : IconButton(
                            tooltip: 'Quitar recordatorio',
                            icon: const Icon(LucideIcons.x, size: 16),
                            onPressed: () => setState(() {
                              _reminderAt = null;
                              _reminderNoteController.clear();
                            }),
                          ),
                  ),
                  child: Text(
                    _reminderAt == null
                        ? 'Sin recordatorio'
                        : '${AppDateUtils.formatShortDate(_reminderAt!)} · '
                              '${AppDateUtils.formatTime12h(_reminderAt!)}',
                    style: TextStyle(
                      color: _reminderAt == null
                          ? colors.textSecondary
                          : colors.textPrimary,
                      fontWeight: _reminderAt == null
                          ? FontWeight.w400
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (_reminderAt != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reminderNoteController,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Nota del recordatorio (opcional)',
                    hintText: 'Ej: consultarle al equipo de tecno',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _assignedUserId,
                decoration: const InputDecoration(
                  labelText: 'Responsable (opcional)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin asignar'),
                  ),
                  for (final u in catalog.users)
                    DropdownMenuItem<String?>(value: u.id, child: Text(u.name)),
                ],
                onChanged: (v) => setState(() => _assignedUserId = v),
              ),
              const SizedBox(height: 16),
              Text(
                'Etiquetas',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              StreamBuilder<List<SupportCaseTagModel>>(
                stream: context.read<SupportCaseRepository>().watchTags(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      'No se pudieron cargar las etiquetas.',
                      style: TextStyle(color: colors.error, fontSize: 12),
                    );
                  }
                  final tags = snapshot.data ?? const [];
                  if (tags.isEmpty) {
                    return Text(
                      'Sin etiquetas todavía.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in tags)
                        FilterChip(
                          label: Text(tag.name),
                          selected: _selectedTags.contains(tag.name),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _selectedTags.add(tag.name);
                            } else {
                              _selectedTags.remove(tag.name);
                            }
                          }),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Crear caso'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
