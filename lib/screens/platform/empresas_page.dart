import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/empresa_model.dart';
import '../../services/empresa_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';

/// Michel's own screen: list every empresa (tenant), create a new one (with
/// its first admin account), and activate/deactivate one — e.g. for
/// non-payment. Only reachable when `AuthProvider.isPlatformOwner` is true
/// (see `PlatformAdminShell`); a tenant's own super_admin never sees this.
class EmpresasPage extends StatefulWidget {
  const EmpresasPage({super.key});

  @override
  State<EmpresasPage> createState() => _EmpresasPageState();
}

class _EmpresasPageState extends State<EmpresasPage> {
  final _repo = EmpresaRepository();
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateEmpresaDialog(context, _repo),
        icon: const Icon(Icons.add),
        label: const Text('Nueva empresa'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar empresa...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: StreamBuilder<List<EmpresaModel>>(
                stream: _repo.watchAllEmpresas(),
                builder: (context, snap) {
                  if (!snap.hasData) return const LoadingIndicator();
                  final empresas = snap.data!
                      .where((e) => e.name.toLowerCase().contains(_query))
                      .toList();
                  if (empresas.isEmpty) {
                    return const EmptyState(
                      message: 'No hay empresas todavía.\nUsa "Nueva empresa" para crear la primera.',
                      icon: LucideIcons.building2,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: empresas.length,
                    separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _EmpresaCard(
                      empresa: empresas[i],
                      onTap: () => _showEmpresaDetailSheet(context, _repo, empresas[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmpresaCard extends StatelessWidget {
  const _EmpresaCard({required this.empresa, required this.onTap});

  final EmpresaModel empresa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: (empresa.activo ? colors.success : colors.error).withValues(alpha: 0.15),
                child: Icon(
                  empresa.activo ? LucideIcons.building2 : LucideIcons.building,
                  color: empresa.activo ? colors.success : colors.error,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      empresa.name,
                      style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      empresa.activo ? 'Activa' : 'Desactivada${empresa.suspendedReason != null ? ' — ${empresa.suspendedReason}' : ''}',
                      style: TextStyle(color: empresa.activo ? colors.success : colors.error, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showCreateEmpresaDialog(BuildContext context, EmpresaRepository repo) async {
  final colors = context.colors;
  final formKey = GlobalKey<FormState>();
  final empresaNameController = TextEditingController();
  final adminNameController = TextEditingController();
  final adminEmailController = TextEditingController();
  final adminPasswordController = TextEditingController();
  bool isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Nueva empresa'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: empresaNameController,
                  decoration: const InputDecoration(labelText: 'Nombre de la empresa'),
                  validator: (v) => Validators.required(v, fieldName: 'El nombre'),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Primer administrador', style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: adminNameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => Validators.required(v, fieldName: 'El nombre'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: adminEmailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: adminPasswordController,
                  decoration: const InputDecoration(labelText: 'Contraseña temporal'),
                  obscureText: true,
                  validator: Validators.password,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: isSaving
                ? null
                : () async {
                    if (!formKey.currentState!.validate()) return;
                    setState(() => isSaving = true);
                    try {
                      await repo.createEmpresa(
                        empresaName: empresaNameController.text.trim(),
                        adminEmail: adminEmailController.text.trim(),
                        adminPassword: adminPasswordController.text,
                        adminName: adminNameController.text.trim(),
                      );
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                        SnackbarUtils.showSuccess(context, 'Empresa creada correctamente');
                      }
                    } on FirebaseFunctionsException catch (e) {
                      setState(() => isSaving = false);
                      if (dialogContext.mounted) {
                        SnackbarUtils.showError(dialogContext, e.message ?? 'No se pudo crear la empresa');
                      }
                    } catch (e) {
                      setState(() => isSaving = false);
                      if (dialogContext.mounted) {
                        SnackbarUtils.showError(dialogContext, SnackbarUtils.firebaseErrorMessage(e));
                      }
                    }
                  },
            child: isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Crear'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showEmpresaDetailSheet(
  BuildContext context,
  EmpresaRepository repo,
  EmpresaModel empresa,
) async {
  final colors = context.colors;
  final reasonController = TextEditingController();
  bool isSaving = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(empresa.name, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              empresa.activo ? 'Esta empresa está activa.' : 'Esta empresa está desactivada.',
              style: TextStyle(color: empresa.activo ? colors.success : colors.error),
            ),
            if (empresa.suspendedReason != null) ...[
              const SizedBox(height: 4),
              Text('Motivo: ${empresa.suspendedReason}', style: TextStyle(color: colors.textSecondary)),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (empresa.activo) ...[
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Motivo de la desactivación (opcional)'),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: colors.error, foregroundColor: Colors.white),
                  icon: const Icon(Icons.block),
                  label: const Text('Desactivar empresa'),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final confirmed = await showConfirmDialog(
                            sheetContext,
                            title: 'Desactivar empresa',
                            message: 'Los usuarios de "${empresa.name}" no podrán iniciar sesión hasta que la reactives. ¿Continuar?',
                            destructive: true,
                            confirmLabel: 'Desactivar',
                          );
                          if (!confirmed) return;
                          setState(() => isSaving = true);
                          try {
                            await repo.toggleEmpresa(
                              empresaId: empresa.id,
                              activo: false,
                              reason: reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
                            );
                            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                          } catch (e) {
                            setState(() => isSaving = false);
                            if (sheetContext.mounted) {
                              SnackbarUtils.showError(sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                            }
                          }
                        },
                ),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: colors.success, foregroundColor: Colors.white),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Reactivar empresa'),
                  onPressed: isSaving
                      ? null
                      : () async {
                          setState(() => isSaving = true);
                          try {
                            await repo.toggleEmpresa(empresaId: empresa.id, activo: true);
                            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                          } catch (e) {
                            setState(() => isSaving = false);
                            if (sheetContext.mounted) {
                              SnackbarUtils.showError(sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                            }
                          }
                        },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
