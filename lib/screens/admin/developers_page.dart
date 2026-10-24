import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/requirement_model.dart';
import '../../services/requirement_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';

/// El equipo técnico al que se le asignan los requerimientos.
///
/// Catálogo propio y no usuarios de CheCu: Andrés, Wilmer y Kelvin están del
/// otro lado, construyendo VinApp, y no entran a esta app. Crearles cuenta
/// sólo para poder nombrarlos sería darles acceso a cosas que no les tocan.
///
/// Michel pidió que fuera editable porque entran y salen del equipo.
class DevelopersPage extends StatefulWidget {
  const DevelopersPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<DevelopersPage> createState() => _DevelopersPageState();
}

class _DevelopersPageState extends State<DevelopersPage> {
  final _nombre = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _agregar() async {
    final n = _nombre.text.trim();
    if (n.isEmpty) return;
    setState(() => _guardando = true);
    try {
      await context.read<RequirementRepository>().addDeveloper(n);
      _nombre.clear();
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _renombrar(DeveloperModel d) async {
    final control = TextEditingController(text: d.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar'),
        content: TextField(controller: control, autofocus: true),
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
    final nuevo = control.text.trim();
    control.dispose();
    if (ok != true || nuevo.isEmpty || !mounted) return;
    await context.read<RequirementRepository>().renameDeveloper(d.id, nuevo);
  }

  Future<void> _eliminar(DeveloperModel d) async {
    final repo = context.read<RequirementRepository>();
    final borrado = await repo.deleteDeveloperIfUnused(d.id);
    if (!mounted) return;
    if (borrado) {
      SnackbarUtils.showSuccess(context, '${d.name} eliminado');
      return;
    }
    // Tiene requerimientos: borrarlo los dejaría con un responsable que no
    // existe, así que se ofrece desactivarlo, que es lo que de verdad pasa
    // cuando alguien sale del equipo.
    final desactivar = await showConfirmDialog(
      context,
      title: 'No se puede eliminar',
      message:
          '${d.name} tiene requerimientos asignados. Si se elimina, esos '
          'requerimientos quedarían sin responsable. ¿Desactivarlo? Deja de '
          'ofrecerse para asignar, pero sigue nombrándose en los que ya tiene.',
      confirmLabel: 'Desactivar',
    );
    if (!desactivar || !mounted) return;
    await repo.setDeveloperActive(d.id, false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final repo = context.watch<RequirementRepository>();

    final cuerpo = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Equipo técnico',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A quién se le pueden asignar los requerimientos. No son '
                'usuarios de CheCu: no entran a la app.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nombre,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        hintText: 'Por ejemplo: Andrés',
                      ),
                      onSubmitted: (_) => _guardando ? null : _agregar(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _guardando ? null : _agregar,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: StreamBuilder<List<DeveloperModel>>(
                  stream: repo.watchDevelopers(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return StreamErrorState(error: snap.error!);
                    }
                    if (!snap.hasData) return const LoadingIndicator();
                    final devs = snap.data!;
                    if (devs.isEmpty) {
                      return const EmptyState(
                        message: 'Todavía no hay nadie en el equipo técnico.',
                        icon: LucideIcons.users,
                      );
                    }
                    return ListView.builder(
                      itemCount: devs.length,
                      itemBuilder: (_, i) {
                        final d = devs[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                            border: Border.all(color: colors.divider),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.user,
                                size: 18,
                                color: d.isActive
                                    ? colors.primary
                                    : colors.textSecondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  d.name,
                                  style: TextStyle(
                                    color: d.isActive
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (!d.isActive)
                                Text(
                                  'Inactivo',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              Switch(
                                value: d.isActive,
                                onChanged: (v) =>
                                    repo.setDeveloperActive(d.id, v),
                              ),
                              IconButton(
                                tooltip: 'Renombrar',
                                icon: Icon(
                                  LucideIcons.pencil,
                                  size: 16,
                                  color: colors.textSecondary,
                                ),
                                onPressed: () => _renombrar(d),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                icon: Icon(
                                  LucideIcons.trash2,
                                  size: 16,
                                  color: colors.error,
                                ),
                                onPressed: () => _eliminar(d),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!widget.showAppBar) return cuerpo;
    return Scaffold(
      appBar: AppBar(title: const Text('Equipo técnico')),
      body: cuerpo,
    );
  }
}
