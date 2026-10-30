import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/requirement_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/requirement_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/requirement_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import 'requirement_create_panel.dart';
import 'requirement_widgets.dart';

/// El detalle de un requerimiento: la descripción completa, en qué punto del
/// recorrido está, quién lo tiene y todo lo que le ha pasado.
///
/// Mover de estado y asignar sólo lo puede hacer quien dirige el área
/// (`manageRequirements`); comentar, cualquiera. Esa es la separación que
/// pidió Michel: Verónica aprueba, pero cualquiera puede aportar contexto.
class RequirementDetailView extends StatefulWidget {
  const RequirementDetailView({
    super.key,
    required this.requirementId,
    this.onClose,
  });

  final String requirementId;
  final VoidCallback? onClose;

  @override
  State<RequirementDetailView> createState() => _RequirementDetailViewState();
}

class _RequirementDetailViewState extends State<RequirementDetailView> {
  final _comentario = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() {
    _comentario.dispose();
    super.dispose();
  }

  ({String id, String name}) get _yo {
    final u = context.read<AuthProvider>().appUser;
    return (id: u?.id ?? '', name: u?.name ?? 'Alguien');
  }

  Future<void> _comentar() async {
    final texto = _comentario.text.trim();
    if (texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      await context.read<RequirementRepository>().addEvent(
        widget.requirementId,
        type: RequirementEvent.comentario,
        text: texto,
        authorId: _yo.id,
        authorName: _yo.name,
      );
      _comentario.clear();
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _cambiarEstado(RequirementModel r, String nuevo) async {
    if (nuevo == r.status) return;
    // Rechazar es la única que no se puede deshacer de un clic: confirma.
    if (nuevo == RequirementStatus.rechazado) {
      final ok = await showConfirmDialog(
        context,
        title: 'Rechazar requerimiento',
        message:
            '¿Marcar ${r.codigo} como rechazado? Queda registrado quién lo '
            'rechazó y cuándo, y se puede reabrir cambiándole el estado.',
        confirmLabel: 'Rechazar',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    try {
      await context.read<RequirementRepository>().changeStatus(
        r.id,
        from: r.status,
        to: nuevo,
        authorId: _yo.id,
        authorName: _yo.name,
      );
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  Future<void> _asignar(RequirementModel r, DeveloperModel? dev) async {
    try {
      await context.read<RequirementRepository>().assignDeveloper(
        r.id,
        developerId: dev?.id,
        developerName: dev?.name ?? '',
        authorId: _yo.id,
        authorName: _yo.name,
      );
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  Future<void> _editarNotasQa(RequirementModel r) async {
    final control = TextEditingController(text: r.qaNotes);
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notas de QA'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: control,
            maxLines: 8,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Qué se probó, qué falta, qué se devolvió…',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final texto = control.text;
    control.dispose();
    if (guardar != true || !mounted) return;
    try {
      await context.read<RequirementRepository>().updateQaNotes(
        r.id,
        notes: texto.trim(),
        authorId: _yo.id,
        authorName: _yo.name,
      );
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<RequirementRepository>();
    final colors = context.colors;
    final puedeGestionar = context.watch<AuthProvider>().hasPermission(
      AppPermissions.manageRequirements,
    );

    return StreamBuilder<RequirementModel?>(
      stream: repo.watchOne(widget.requirementId),
      builder: (context, snap) {
        if (snap.hasError) return StreamErrorState(error: snap.error!);
        if (!snap.hasData && snap.connectionState != ConnectionState.active) {
          return const LoadingIndicator();
        }
        final r = snap.data;
        if (r == null) {
          return const EmptyState(
            message: 'Este requerimiento ya no existe.',
            icon: LucideIcons.fileX,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _encabezado(r, colors, puedeGestionar),
            const Divider(height: 1),
            Expanded(
              child: SelectionArea(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    _ficha(r, colors, puedeGestionar),
                    const SizedBox(height: AppSpacing.md),
                    _bloque(
                      colors,
                      'DESCRIPCIÓN',
                      SelectableText(
                        r.description,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _notasQa(r, colors, puedeGestionar),
                    const SizedBox(height: AppSpacing.md),
                    _linea(r, colors),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _cajaComentario(colors),
          ],
        );
      },
    );
  }

  /// Borra el requerimiento, preguntando antes.
  ///
  /// No hay papelera de requerimientos, así que esto es definitivo y se lleva
  /// también su historia. Por eso dice el código y para quién era: a Michel
  /// le quedaron tres REQ de prueba seguidos y confundirse de fila es fácil.
  Future<void> _eliminar(RequirementModel r) async {
    final confirma = await showConfirmDialog(
      context,
      title: 'Eliminar ${r.codigo}',
      message:
          '¿Eliminar "${r.paraQuien}" de forma permanente, con todo su '
          'seguimiento? No se puede deshacer.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirma || !mounted) return;
    try {
      await context.read<RequirementRepository>().delete(r.id);
      if (!mounted) return;
      widget.onClose?.call();
      if (mounted) SnackbarUtils.showSuccess(context, '${r.codigo} eliminado');
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  Widget _encabezado(
    RequirementModel r,
    AppColorsExtension colors,
    bool puedeGestionar,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(LucideIcons.lightbulb, color: colors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${r.codigo} · ${r.paraQuien}',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (puedeGestionar)
            IconButton(
              tooltip: 'Editar',
              icon: Icon(LucideIcons.pencil, color: colors.primary, size: 18),
              onPressed: () => showRequirementEditSheet(context, r),
            ),
          if (puedeGestionar)
            IconButton(
              tooltip: 'Eliminar',
              icon: Icon(LucideIcons.trash2, color: colors.error, size: 18),
              onPressed: () => _eliminar(r),
            ),
          if (widget.onClose != null)
            IconButton(
              icon: Icon(LucideIcons.x, color: colors.textSecondary),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _ficha(
    RequirementModel r,
    AppColorsExtension colors,
    bool puedeGestionar,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            RequirementBadge.estado(r.status),
            RequirementBadge.tipo(r.type),
            RequirementBadge.prioridad(r.priority),
            RequirementModuleChip(module: r.module),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Recibido el ${AppDateUtils.formatShortDate(r.receivedAt)}'
          '${r.receivedByName.isEmpty ? '' : ' por ${r.receivedByName}'}'
          '${r.source.isEmpty ? '' : ' · ${r.source}'}',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        // De dónde salió, cuando salió de un caso de soporte. Es la mitad de
        // la historia: sin esto el requerimiento aparece sin antecedentes y
        // nadie recuerda qué se le respondió ya al cliente.
        if (r.vieneDeUnCaso) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.lifeBuoy, size: 13, color: colors.textSecondary),
              const SizedBox(width: 5),
              Text(
                'Viene del caso de soporte ${r.codigoCaso}',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (puedeGestionar) ...[
          _selectorEstado(r, colors),
          const SizedBox(height: 10),
          _selectorResponsable(r, colors),
        ] else ...[
          Text(
            r.estaAsignado
                ? 'Responsable: ${r.developerName}'
                : 'Sin responsable asignado',
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          // Sin esto, quien no tiene el permiso ve una ficha sin controles y
          // no sabe si es que no se puede o si algo se rompió.
          Row(
            children: [
              Icon(LucideIcons.lock, size: 13, color: colors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Solo quien tiene el permiso "Aprobar y asignar '
                  'requerimientos" puede editarlo o moverlo de estado.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _selectorEstado(RequirementModel r, AppColorsExtension colors) {
    return Row(
      children: [
        Icon(LucideIcons.gitBranch, size: 16, color: colors.textSecondary),
        const SizedBox(width: 8),
        Text('Estado:', style: TextStyle(color: colors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButton<String>(
            value: r.status,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            dropdownColor: colors.surface,
            items: [
              for (final s in RequirementStatus.all)
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) => v == null ? null : _cambiarEstado(r, v),
          ),
        ),
      ],
    );
  }

  Widget _selectorResponsable(RequirementModel r, AppColorsExtension colors) {
    final repo = context.read<RequirementRepository>();
    return StreamBuilder<List<DeveloperModel>>(
      stream: repo.watchDevelopers(),
      builder: (context, snap) {
        final todos = snap.data ?? const <DeveloperModel>[];
        // Los inactivos no se ofrecen, pero el que ya está asignado sí
        // aparece aunque haya salido del equipo: si no, el desplegable se
        // vería vacío y parecería que nadie lo tiene.
        final opciones = [
          for (final d in todos)
            if (d.isActive || d.id == r.developerId) d,
        ];
        return Row(
          children: [
            Icon(LucideIcons.userCog, size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text('Responsable:', style: TextStyle(color: colors.textSecondary)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String?>(
                value: opciones.any((d) => d.id == r.developerId)
                    ? r.developerId
                    : null,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                dropdownColor: colors.surface,
                hint: const Text('Sin asignar'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin asignar'),
                  ),
                  for (final d in opciones)
                    DropdownMenuItem<String?>(
                      value: d.id,
                      child: Text(d.isActive ? d.name : '${d.name} (inactivo)'),
                    ),
                ],
                onChanged: (v) => _asignar(
                  r,
                  v == null ? null : opciones.firstWhere((d) => d.id == v),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _notasQa(
    RequirementModel r,
    AppColorsExtension colors,
    bool puedeGestionar,
  ) {
    return _bloque(
      colors,
      'NOTAS DE QA',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.qaNotes.isEmpty ? 'Sin notas todavía.' : r.qaNotes,
            style: TextStyle(
              color: r.qaNotes.isEmpty
                  ? colors.textSecondary
                  : colors.textPrimary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (puedeGestionar) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => _editarNotasQa(r),
              icon: const Icon(LucideIcons.pencil, size: 15),
              label: Text(
                r.qaNotes.isEmpty ? 'Escribir notas' : 'Editar notas',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _linea(RequirementModel r, AppColorsExtension colors) {
    final repo = context.read<RequirementRepository>();
    return StreamBuilder<List<RequirementEvent>>(
      stream: repo.watchEvents(r.id),
      builder: (context, snap) {
        final eventos = (snap.data ?? const <RequirementEvent>[]).reversed
            .toList();
        return _bloque(
          colors,
          'LÍNEA DE TIEMPO',
          eventos.isEmpty
              ? Text(
                  'Sin movimientos.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in eventos)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _iconoDe(e.type),
                              size: 15,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.text,
                                    style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${e.authorName}'
                                    '${e.createdAt == null ? '' : ' · ${AppDateUtils.formatShortDate(e.createdAt!)}'}',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  IconData _iconoDe(String tipo) => switch (tipo) {
    RequirementEvent.creado => LucideIcons.plusCircle,
    RequirementEvent.estado => LucideIcons.gitBranch,
    RequirementEvent.asignado => LucideIcons.userCog,
    RequirementEvent.notaQa => LucideIcons.clipboardCheck,
    RequirementEvent.editado => LucideIcons.pencil,
    _ => LucideIcons.messageSquare,
  };

  Widget _bloque(AppColorsExtension colors, String titulo, Widget hijo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mismo peso y mismo color que los de Casos de Soporte: son el
        // mismo tipo de letrero y no tienen por qué verse distintos.
        Text(
          titulo,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        hijo,
      ],
    );
  }

  Widget _cajaComentario(AppColorsExtension colors) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _comentario,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Escribe un comentario…',
              ),
              onSubmitted: (_) => _enviando ? null : _comentar(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _enviando ? null : _comentar,
            child: const Text('Comentar'),
          ),
        ],
      ),
    );
  }
}
