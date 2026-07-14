import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/auth_service.dart';
import '../../services/task_repository.dart';
import '../../services/user_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';

enum _UserStatusFilter { all, active, inactive }

/// Admin: list of `users`, change role/group, reset password, view FCM
/// tokens, and manage the active/inactive lifecycle (Sprint 7.3.1).
class UsersPage extends StatefulWidget {
  const UsersPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  _UserStatusFilter _filter = _UserStatusFilter.all;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final colors = context.colors;
    final users = List<AppUser>.from(catalog.users)
      ..sort((a, b) => a.name.compareTo(b.name));
    final filtered = users.where((u) {
      switch (_filter) {
        case _UserStatusFilter.active:
          return u.isActive;
        case _UserStatusFilter.inactive:
          return !u.isActive;
        case _UserStatusFilter.all:
          return true;
      }
    }).toList();

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _StatusFilterChip(
                label: 'Todos',
                selected: _filter == _UserStatusFilter.all,
                onTap: () => setState(() => _filter = _UserStatusFilter.all),
              ),
              const SizedBox(width: 8),
              _StatusFilterChip(
                label: 'Activos',
                selected: _filter == _UserStatusFilter.active,
                onTap: () => setState(() => _filter = _UserStatusFilter.active),
              ),
              const SizedBox(width: 8),
              _StatusFilterChip(
                label: 'Inactivos',
                selected: _filter == _UserStatusFilter.inactive,
                onTap: () => setState(() => _filter = _UserStatusFilter.inactive),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  message: 'No hay usuarios para este filtro.',
                  icon: LucideIcons.users,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
                      ),
                      child: ListTile(
                        leading: Icon(LucideIcons.userCircle, color: colors.primary, size: 28),
                        title: Text(user.name, style: TextStyle(color: colors.textPrimary)),
                        subtitle: Text(
                          user.email,
                          style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _Tag(label: AuthService.roleLabel(user.role)),
                            if (user.groupId != null) _Tag(label: catalog.groupName(user.groupId)),
                            _StatusBadge(isActive: user.isActive),
                          ],
                        ),
                        onTap: () => _showUserDetailSheet(context, user),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
    final fab = FloatingActionButton(
      onPressed: () => _showCreateUserDialog(context),
      child: const Icon(LucideIcons.userPlus),
    );
    if (!widget.showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.2) : colors.background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? colors.primary : colors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.primary : colors.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = isActive ? colors.success : colors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        isActive ? 'Activo' : 'Inactivo',
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: colors.primary, fontSize: 10)),
    );
  }
}

Future<void> _showUserDetailSheet(BuildContext context, AppUser user) async {
  final colors = context.colors;
  final catalog = context.read<CatalogProvider>();
  final userRepo = context.read<UserRepository>();
  final authService = context.read<AuthService>();
  final taskRepo = context.read<TaskRepository>();
  final currentUserId = context.read<AuthProvider>().appUser?.id;

  String selectedRole = user.role;
  String? selectedGroupId = user.groupId;
  bool tokensExpanded = false;
  bool isUserActive = user.isActive;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.userCircle, color: colors.primary, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              user.email,
                              style: TextStyle(color: colors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Rol', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    dropdownColor: colors.surface,
                    items: [
                      DropdownMenuItem(
                        value: AppRoles.superAdmin,
                        child: Text(AuthService.roleLabel(AppRoles.superAdmin)),
                      ),
                      DropdownMenuItem(
                        value: AppRoles.trabajadorNormal,
                        child: Text(AuthService.roleLabel(AppRoles.trabajadorNormal)),
                      ),
                    ],
                    onChanged: (value) async {
                      if (value == null || value == selectedRole) return;
                      if (user.id == currentUserId && value != AppRoles.superAdmin) {
                        final confirm = await showConfirmDialog(
                          sheetContext,
                          title: 'Cambiar tu propio rol',
                          message:
                              'Estás a punto de quitarte el rol de administrador. '
                              'Podrías perder acceso al panel de administración. '
                              '¿Deseas continuar?',
                          confirmLabel: 'Continuar',
                          destructive: true,
                        );
                        if (!confirm) return;
                      }
                      try {
                        await userRepo.updateRole(user.id, value);
                        setState(() => selectedRole = value);
                        if (sheetContext.mounted) {
                          SnackbarUtils.showSuccess(sheetContext, 'Rol actualizado');
                        }
                      } catch (e) {
                        if (sheetContext.mounted) {
                          SnackbarUtils.showError(
                              sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Grupo', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedGroupId,
                    dropdownColor: colors.surface,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Sin grupo')),
                      for (final group in catalog.groups)
                        DropdownMenuItem<String?>(value: group.id, child: Text(group.name)),
                    ],
                    onChanged: (value) async {
                      if (value == selectedGroupId) return;
                      try {
                        await userRepo.updateGroup(user.id, value);
                        setState(() => selectedGroupId = value);
                        if (sheetContext.mounted) {
                          SnackbarUtils.showSuccess(sheetContext, 'Grupo actualizado');
                        }
                      } catch (e) {
                        if (sheetContext.mounted) {
                          SnackbarUtils.showError(
                              sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await showConfirmDialog(
                        sheetContext,
                        title: 'Restablecer contraseña',
                        message:
                            'Se enviará un correo a ${user.email} con instrucciones '
                            'para restablecer la contraseña. ¿Continuar?',
                        confirmLabel: 'Enviar',
                      );
                      if (!confirm) return;
                      try {
                        await authService.sendPasswordResetEmail(user.email);
                        if (sheetContext.mounted) {
                          SnackbarUtils.showSuccess(
                              sheetContext, 'Correo de restablecimiento enviado');
                        }
                      } catch (e) {
                        if (sheetContext.mounted) {
                          SnackbarUtils.showError(
                              sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                        }
                      }
                    },
                    icon: const Icon(LucideIcons.key),
                    label: const Text('Restablecer contraseña'),
                  ),
                  const SizedBox(height: 12),
                  if (isUserActive)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(color: colors.error),
                      ),
                      onPressed: () async {
                        final confirm = await showConfirmDialog(
                          sheetContext,
                          title: 'Desactivar usuario',
                          message: '¿Deseas desactivar este usuario?\n\n'
                              'El usuario dejará de tener acceso a CheCu, '
                              'no recibirá nuevas tareas ni notificaciones.',
                          confirmLabel: 'Desactivar',
                          destructive: true,
                        );
                        if (!confirm) return;
                        try {
                          await userRepo.setActive(user.id, false);
                          setState(() => isUserActive = false);
                          if (sheetContext.mounted) {
                            SnackbarUtils.showSuccess(sheetContext, 'Usuario desactivado');
                          }
                        } catch (e) {
                          if (sheetContext.mounted) {
                            SnackbarUtils.showError(
                                sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.userX),
                      label: const Text('Desactivar usuario'),
                    )
                  else ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.success,
                        side: BorderSide(color: colors.success),
                      ),
                      onPressed: () async {
                        final confirm = await showConfirmDialog(
                          sheetContext,
                          title: 'Reactivar usuario',
                          message: '¿Deseas reactivar este usuario?\n\n'
                              'Recuperará acceso a la plataforma.',
                          confirmLabel: 'Reactivar',
                        );
                        if (!confirm) return;
                        try {
                          await userRepo.setActive(user.id, true);
                          setState(() => isUserActive = true);
                          if (sheetContext.mounted) {
                            SnackbarUtils.showSuccess(sheetContext, 'Usuario reactivado');
                          }
                        } catch (e) {
                          if (sheetContext.mounted) {
                            SnackbarUtils.showError(
                                sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.userCheck),
                      label: const Text('Reactivar usuario'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(color: colors.error),
                      ),
                      onPressed: () async {
                        final history = await taskRepo.getUserTaskHistory(
                          user.id,
                          completedStatusId: catalog.completedStatusId,
                          rescheduledStatusId: catalog.rescheduledStatusId,
                        );

                        if (history.hasHistory) {
                          if (!sheetContext.mounted) return;
                          await showInfoDialog(
                            sheetContext,
                            title: 'No es posible eliminar este usuario',
                            message: 'Se encontraron registros históricos asociados:\n\n'
                                '• Tareas asignadas: ${history.assigned}\n'
                                '• Tareas completadas: ${history.completed}\n'
                                '• Tareas reprogramadas: ${history.rescheduled}\n\n'
                                'Para conservar la integridad de los datos, '
                                'desactiva el usuario en lugar de eliminarlo.',
                          );
                          return;
                        }

                        if (!sheetContext.mounted) return;
                        final confirm = await showConfirmDialog(
                          sheetContext,
                          title: 'Eliminar permanentemente',
                          message:
                              'Esta acción eliminará a ${user.name} de forma '
                              'permanente y no se puede deshacer. ¿Deseas continuar?',
                          confirmLabel: 'Eliminar',
                          destructive: true,
                        );
                        if (!confirm) return;

                        try {
                          await authService.deleteUserPermanently(user.id);
                          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                          if (context.mounted) {
                            SnackbarUtils.showSuccess(
                                context, 'Usuario eliminado permanentemente');
                          }
                        } on FirebaseFunctionsException catch (e) {
                          if (sheetContext.mounted) {
                            SnackbarUtils.showError(
                                sheetContext, e.message ?? 'No se pudo eliminar el usuario');
                          }
                        } catch (e) {
                          if (sheetContext.mounted) {
                            SnackbarUtils.showError(
                                sheetContext, SnackbarUtils.firebaseErrorMessage(e));
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.trash2),
                      label: const Text('Eliminar permanentemente'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setState(() => tokensExpanded = !tokensExpanded),
                    child: Row(
                      children: [
                        Icon(LucideIcons.smartphone, color: colors.primary, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Tokens FCM (${user.fcmTokens.length})',
                          style: TextStyle(color: colors.textPrimary, fontSize: 13),
                        ),
                        const Spacer(),
                        Icon(
                          tokensExpanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                          color: colors.textSecondary,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                  if (tokensExpanded) ...[
                    const SizedBox(height: 8),
                    if (user.fcmTokens.isEmpty)
                      Text(
                        'Este usuario no tiene dispositivos registrados.',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      )
                    else
                      for (final token in user.fcmTokens)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            token,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> _showCreateUserDialog(BuildContext context) async {
  final colors = context.colors;
  final authService = context.read<AuthService>();
  final catalog = context.read<CatalogProvider>();
  final formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  String role = AppRoles.trabajadorNormal;
  String? groupId;
  bool isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: const Text('Crear usuario'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      autofocus: true,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (v) => Validators.required(v, fieldName: 'El nombre'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: passwordController,
                      obscureText: true,
                      style: TextStyle(color: colors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Contraseña temporal'),
                      validator: Validators.password,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      dropdownColor: colors.surface,
                      decoration: const InputDecoration(labelText: 'Rol'),
                      items: [
                        DropdownMenuItem(
                          value: AppRoles.trabajadorNormal,
                          child: Text(AuthService.roleLabel(AppRoles.trabajadorNormal)),
                        ),
                        DropdownMenuItem(
                          value: AppRoles.superAdmin,
                          child: Text(AuthService.roleLabel(AppRoles.superAdmin)),
                        ),
                      ],
                      onChanged: (v) => setState(() => role = v ?? role),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: groupId,
                      dropdownColor: colors.surface,
                      decoration: const InputDecoration(labelText: 'Grupo (opcional)'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Sin grupo')),
                        for (final group in catalog.groups)
                          DropdownMenuItem<String?>(value: group.id, child: Text(group.name)),
                      ],
                      onChanged: (v) => setState(() => groupId = v),
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
                          await authService.createUser(
                            email: emailController.text.trim(),
                            password: passwordController.text,
                            name: nameController.text.trim(),
                            role: role,
                            groupId: groupId,
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                            SnackbarUtils.showSuccess(context, 'Usuario creado correctamente');
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            SnackbarUtils.showError(
                                dialogContext, SnackbarUtils.firebaseErrorMessage(e));
                          }
                          setState(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear'),
              ),
            ],
          );
        },
      );
    },
  );
}
