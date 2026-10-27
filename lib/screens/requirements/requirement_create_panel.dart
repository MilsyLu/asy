import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/requirement_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/client_model.dart';
import '../../models/requirement_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/requirement_repository.dart';
import 'requirement_module_dialog.dart';

/// Lo que trae un caso de soporte que se va a convertir en requerimiento.
///
/// No es el caso entero: es lo poco que sirve de los dos lados —de quién es,
/// qué pidió y de qué caso salió—. El resto (tipo, módulo, prioridad) lo
/// decide quien convierte, porque son preguntas de desarrollo que el caso no
/// responde.
class RequirementPrefill {
  const RequirementPrefill({
    required this.descripcion,
    required this.clientId,
    required this.clientName,
    required this.supportCaseId,
    required this.supportCaseNumber,
  });

  final String descripcion;
  final String? clientId;
  final String clientName;
  final String supportCaseId;
  final int supportCaseNumber;

  String get codigoCaso => 'CS-${supportCaseNumber.toString().padLeft(4, '0')}';
}

/// Abre el formulario para registrar un requerimiento nuevo.
///
/// Con [prefill] llega con los datos de un caso de soporte ya puestos: es el
/// botón "Pasar a requerimiento" del caso.
/// Devuelve `true` si se llegó a registrar algo, para que quien lo abrió
/// —el botón "Pasar a requerimiento" de un caso de soporte— sepa si anotar
/// la conversión o no. Cerrar con Cancelar devuelve `false`.
Future<bool> showRequirementCreateSheet(
  BuildContext context, {
  RequirementPrefill? prefill,
}) async {
  final creado = await showDialog<bool>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 640,
        child: RequirementCreatePanel(prefill: prefill),
      ),
    ),
  );
  return creado ?? false;
}

/// Abre el mismo formulario para corregir uno que ya existe.
///
/// El mismo widget y no una copia: son los mismos ocho campos con las mismas
/// reglas, y dos formularios parecidos es la forma más segura de que uno se
/// quede sin la validación que el otro sí tiene.
Future<void> showRequirementEditSheet(
  BuildContext context,
  RequirementModel requerimiento,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 640,
        child: RequirementCreatePanel(existente: requerimiento),
      ),
    ),
  );
}

/// Formulario de alta de un requerimiento.
///
/// Lo que la hoja de cálculo pedía escribir y casi nunca se escribía —la
/// fecha de recepción, quién lo recibió, el número— aquí no se pregunta: lo
/// pone la app. Por eso no hay campo de fecha ni de número.
class RequirementCreatePanel extends StatefulWidget {
  const RequirementCreatePanel({
    super.key,
    this.existente,
    this.prefill,
    this.enPanel = false,
  });

  /// Null = alta nueva. Con valor, el formulario corrige ese requerimiento.
  final RequirementModel? existente;

  /// Datos de un caso de soporte que se está convirtiendo en requerimiento.
  final RequirementPrefill? prefill;

  /// Embebido en el panel lateral de la pantalla, no dentro de una ventana.
  ///
  /// Cambia dos cosas: al guardar no cierra nada —se queda listo para el
  /// siguiente, como el "Nueva tarea" de la Agenda diaria— y no muestra el
  /// botón Cancelar, que no tendría qué cancelar.
  final bool enPanel;

  @override
  State<RequirementCreatePanel> createState() => _RequirementCreatePanelState();
}

class _RequirementCreatePanelState extends State<RequirementCreatePanel> {
  final _formKey = GlobalKey<FormState>();
  final _descripcion = TextEditingController();

  late String _origen;
  late String _tipo;
  late String _modulo;
  late String _prioridad;
  late String _area;
  final _clientes = <ClientModel>[];
  bool _guardando = false;

  bool get _editando => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _origen = e?.origin ?? RequirementOrigin.cliente;
    _tipo = e?.type ?? RequirementType.solicitudes;
    // Un valor que ya no está en la lista —un módulo renombrado desde que se
    // importó la hoja— dejaría el desplegable sin coincidencia y reventaría.
    // El que trae el requerimiento si lo reconocemos; si no, "Otros". Un
    // valor suelto dejaría el desplegable sin coincidencia.
    _modulo = (e?.module.isNotEmpty ?? false)
        ? e!.module
        : RequirementModule.otros;
    _prioridad = RequirementPriority.all.contains(e?.priority)
        ? e!.priority
        : RequirementPriority.sinPrioridad;
    _area = RequirementSource.all.contains(e?.source)
        ? e!.source
        : RequirementSource.all.first;
    _descripcion.text = e?.description ?? widget.prefill?.descripcion ?? '';
  }

  /// Los clientes se resuelven en el primer `build`: el catálogo llega por
  /// provider y en `initState` todavía no se puede leer.
  bool _clientesCargados = false;

  void _cargarClientes() {
    if (_clientesCargados) return;
    _clientesCargados = true;
    final catalogo = context.read<CatalogProvider>();
    final e = widget.existente;
    if (e != null) {
      if (e.clientIds.isEmpty) return;
      _clientes.addAll([
        for (final c in catalogo.clients)
          if (e.clientIds.contains(c.id)) c,
      ]);
      return;
    }
    // Viene de un caso de soporte: su cliente entra ya elegido. Sólo si el
    // caso traía un cliente del catálogo — hay casos escritos con el nombre
    // a mano, y ahí no hay a quién enlazar.
    final previo = widget.prefill;
    if (previo?.clientId == null) return;
    _clientes.addAll([
      for (final c in catalogo.clients)
        if (c.id == previo!.clientId) c,
    ]);
  }

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  /// Deja el formulario como recién abierto, para el siguiente requerimiento.
  ///
  /// El `reset()` va primero: `FormState.reset()` no vacía los campos, los
  /// devuelve a su valor inicial, que para un campo con controlador es el
  /// texto de la última reconstrucción. Llamándolo después de `clear()`
  /// reescribe lo que se acaba de borrar — es exactamente lo que hacía que
  /// "Limpiar" no limpiara en el panel de Nueva tarea.
  void _limpiar() {
    _formKey.currentState?.reset();
    _descripcion.clear();
    setState(() {
      _clientes.clear();
      _origen = RequirementOrigin.cliente;
      _tipo = RequirementType.solicitudes;
      _modulo = RequirementModule.otros;
      _prioridad = RequirementPriority.sinPrioridad;
    });
  }

  Future<void> _elegirClientes() async {
    final catalog = context.read<CatalogProvider>();
    final elegidos = {for (final c in _clientes) c.id};
    final busqueda = TextEditingController();

    final res = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final q = busqueda.text.trim().toLowerCase();
          final lista = [
            for (final c in catalog.clients)
              if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
          ];
          return AlertDialog(
            title: const Text('¿Quién lo pidió?'),
            content: SizedBox(
              width: 420,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: busqueda,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar cliente…',
                      prefixIcon: Icon(LucideIcons.search, size: 18),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (_, i) {
                        final c = lista[i];
                        return CheckboxListTile(
                          dense: true,
                          value: elegidos.contains(c.id),
                          title: Text(c.name),
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              elegidos.add(c.id);
                            } else {
                              elegidos.remove(c.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(elegidos),
                child: const Text('Listo'),
              ),
            ],
          );
        },
      ),
    );
    busqueda.dispose();
    if (res == null || !mounted) return;
    setState(() {
      _clientes
        ..clear()
        ..addAll([
          for (final c in context.read<CatalogProvider>().clients)
            if (res.contains(c.id)) c,
        ]);
    });
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Un requerimiento de cliente sin cliente es justo lo que hacía ilegible
    // la hoja: 5 de 48 filas no decían de quién era.
    if (_origen == RequirementOrigin.cliente && _clientes.isEmpty) {
      SnackbarUtils.showError(context, 'Elige al menos un cliente.');
      return;
    }

    setState(() => _guardando = true);
    final usuario = context.read<AuthProvider>().appUser;
    final repo = context.read<RequirementRepository>();
    final ids = [for (final c in _clientes) c.id];
    final nombres = [for (final c in _clientes) c.name];
    try {
      if (_editando) {
        await repo.updateDetails(
          widget.existente!.id,
          origin: _origen,
          clientIds: ids,
          clientNames: nombres,
          type: _tipo,
          module: _modulo,
          description: _descripcion.text.trim(),
          priority: _prioridad,
          source: _area,
          authorId: usuario?.id ?? '',
          authorName: usuario?.name ?? 'Alguien',
        );
      } else {
        await repo.create(
          origin: _origen,
          clientIds: ids,
          clientNames: nombres,
          type: _tipo,
          module: _modulo,
          description: _descripcion.text.trim(),
          priority: _prioridad,
          source: _area,
          createdById: usuario?.id ?? '',
          createdByName: usuario?.name ?? 'Alguien',
          supportCaseId: widget.prefill?.supportCaseId,
          supportCaseNumber: widget.prefill?.supportCaseNumber,
        );
      }
      if (!mounted) return;
      if (widget.enPanel) {
        _limpiar();
      } else {
        Navigator.of(context).pop(true);
      }
      SnackbarUtils.showSuccess(
        context,
        _editando ? 'Requerimiento actualizado' : 'Requerimiento registrado',
      );
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _cargarClientes();
    final colors = context.colors;
    final esDeCliente = _origen == RequirementOrigin.cliente;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.lightbulb, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _editando
                          ? 'Editar ${widget.existente!.codigo}'
                          : widget.prefill == null
                          ? 'Nuevo requerimiento'
                          : 'Nuevo requerimiento desde '
                                '${widget.prefill!.codigoCaso}',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: RequirementOrigin.cliente,
                    label: Text('Lo pidió un cliente'),
                  ),
                  ButtonSegment(
                    value: RequirementOrigin.interno,
                    label: Text('Interno'),
                  ),
                ],
                selected: {_origen},
                onSelectionChanged: (s) => setState(() => _origen = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              if (esDeCliente) ...[
                InkWell(
                  onTap: _elegirClientes,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Clientes que lo pidieron',
                      prefixIcon: Icon(
                        LucideIcons.users,
                        color: colors.primary,
                      ),
                    ),
                    child: Text(
                      _clientes.isEmpty
                          ? 'Elegir…'
                          : _clientes.map((c) => c.name).join(', '),
                      style: TextStyle(
                        color: _clientes.isEmpty
                            ? colors.textSecondary
                            : colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextFormField(
                controller: _descripcion,
                maxLines: 8,
                minLines: 4,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Descripción del requerimiento',
                  alignLabelWithHint: true,
                  hintText:
                      'Qué pide el cliente, en qué pantalla, y para qué lo '
                      'necesita.',
                ),
                validator: (v) => (v == null || v.trim().length < 10)
                    ? 'Describe el requerimiento (mínimo 10 caracteres).'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _desplegable(
                      'Tipo',
                      _tipo,
                      RequirementType.all,
                      (v) => setState(() => _tipo = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _desplegable(
                      'Módulo',
                      _modulo,
                      context.watch<CatalogProvider>().requirementModules,
                      (v) => setState(() => _modulo = v),
                      conAgregar: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _desplegable(
                      'Prioridad',
                      _prioridad,
                      RequirementPriority.all,
                      (v) => setState(() => _prioridad = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _desplegable(
                      'Recibido por',
                      _area,
                      RequirementSource.all,
                      (v) => setState(() => _area = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  if (!widget.enPanel) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _guardando
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.check, size: 18),
                      label: Text(
                        _guardando
                            ? 'Guardando…'
                            : (_editando ? 'Guardar cambios' : 'Registrar'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desplegable(
    String etiqueta,
    String valor,
    List<String> opciones,
    ValueChanged<String> onChanged, {
    bool conAgregar = false,
  }) {
    return DropdownButtonFormField<String>(
      // Un valor que no está en la lista deja el desplegable sin coincidencia
      // y revienta: pasa con un módulo que el equipo agregó y todavía no ha
      // llegado por el stream, o con uno escrito distinto en la hoja vieja.
      initialValue: opciones.contains(valor) ? valor : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: etiqueta),
      items: [
        for (final o in opciones) DropdownMenuItem(value: o, child: Text(o)),
        if (conAgregar) agregarModuloItem(context),
      ],
      onChanged: (v) async {
        if (v == null) return;
        if (v != kAgregarModulo) {
          onChanged(v);
          return;
        }
        final creado = await pedirModuloNuevo(context);
        // Queda elegido de una vez: agregarlo es justamente lo que uno hace
        // cuando el módulo que necesita no estaba.
        if (creado != null && mounted) onChanged(creado);
      },
    );
  }
}
