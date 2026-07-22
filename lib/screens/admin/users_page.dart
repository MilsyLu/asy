import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/validators.dart';
import '../../models/app_user.dart';
import '../../models/group_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/auth_service.dart';
import '../../services/task_repository.dart';
import '../../services/user_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/side_panel_shell.dart';
import '../../widgets/user_avatar.dart';

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
  String? _groupFilter;
  String? _roleFilter;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final isMobile = context.isMobile;
    final users = List<AppUser>.from(catalog.users)
      ..sort((a, b) => a.name.compareTo(b.name));
    final query = _searchQuery.trim().toLowerCase();
    final filtered = users.where((u) {
      if (_filter == _UserStatusFilter.active && !u.isActive) return false;
      if (_filter == _UserStatusFilter.inactive && u.isActive) return false;
      if (_groupFilter == AppFilterValues.noGroup) {
        if (u.groupId != null) return false;
      } else if (_groupFilter != null && u.groupId != _groupFilter) {
        return false;
      }
      if (_roleFilter != null && u.role != _roleFilter) return false;
      if (query.isNotEmpty &&
          !u.name.toLowerCase().contains(query) &&
          !u.email.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();

    final groups = List.of(catalog.groups)..sort((a, b) => a.name.compareTo(b.name));

    final filtersBlock = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _UserSearchField(controller: _searchController, onChanged: (v) => setState(() => _searchQuery = v)),
                    const SizedBox(height: 8),
                    _GroupFilterDropdown(
                      groups: groups,
                      value: _groupFilter,
                      onChanged: (v) => setState(() => _groupFilter = v),
                    ),
                    const SizedBox(height: 8),
                    _RoleFilterDropdown(
                      value: _roleFilter,
                      onChanged: (v) => setState(() => _roleFilter = v),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _UserSearchField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _GroupFilterDropdown(
                            groups: groups,
                            value: _groupFilter,
                            onChanged: (v) => setState(() => _groupFilter = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _RoleFilterDropdown(
                            value: _roleFilter,
                            onChanged: (v) => setState(() => _roleFilter = v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
          const SizedBox(height: 10),
          Row(
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
        ],
      ),
    );

    Widget buildList({required bool shrink}) {
      if (filtered.isEmpty) {
        return const EmptyState(
          message: 'No hay usuarios para estos filtros.',
          icon: LucideIcons.users,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shrinkWrap: shrink,
        physics: shrink ? const NeverScrollableScrollPhysics() : null,
        itemCount: filtered.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final user = filtered[index];
          return _UserCard(
            user: user,
            groupName: user.groupId != null ? catalog.groupName(user.groupId) : null,
            onTap: () => _showUserDetailSheet(context, user),
          );
        },
      );
    }

    Widget body;
    if (isMobile) {
      body = Column(children: [filtersBlock, Expanded(child: buildList(shrink: false))]);
    } else {
      // Same rule as Equipos: below ~900px of *actual* available width (not
      // just device category — a collapsed vs. expanded sidebar changes this
      // just as much as screen size), stack the panel under the list instead
      // of squeezing both side by side into illegibility.
      body = LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 900;
          const panel = _CreateUserPanel(key: ValueKey('create-user'));

          if (sideBySide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: AppLayout.contentMaxWidthWide),
                      child: Column(
                        children: [filtersBlock, Expanded(child: buildList(shrink: false))],
                      ),
                    ),
                  ),
                ),
                Padding(
                  // Extra top offset (vs. the 12px used by Equipos/Estados)
                  // to realign with the list, which now starts one row
                  // lower here — the Rol filter added a second filters row.
                  padding: const EdgeInsets.fromLTRB(0, 68, 16, 16),
                  child: SizedBox(width: 320, child: panel),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                filtersBlock,
                buildList(shrink: true),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: panel,
                ),
              ],
            ),
          );
        },
      );
    }

    // Tablet/desktop: the panel replaces the FAB for creating a user, so no
    // FAB there. Mobile keeps it (no persistent panel to hold the form).
    final fab = isMobile
        ? FloatingActionButton(
            onPressed: () => _showCreateUserDialog(context),
            child: const Icon(LucideIcons.userPlus),
          )
        : null;
    if (!widget.showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('Usuarios')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

/// Tablet/desktop always-visible right panel for creating a user — mirrors
/// [_showCreateUserDialog]'s fields, embedded instead of behind a FAB dialog.
/// Stays in place after a successful save (fields just clear) so an admin
/// can add several users in a row.
class _CreateUserPanel extends StatefulWidget {
  const _CreateUserPanel({super.key});

  @override
  State<_CreateUserPanel> createState() => _CreateUserPanelState();
}

class _CreateUserPanelState extends State<_CreateUserPanel> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = AppRoles.trabajadorNormal;
  String? _groupId;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final authService = context.read<AuthService>();
    try {
      await authService.createUser(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        role: _role,
        groupId: _groupId,
      );
      if (mounted) {
        _formKey.currentState!.reset();
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        setState(() => _groupId = null);
        SnackbarUtils.showSuccess(context, 'Usuario creado correctamente');
      }
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    return SidePanelShell(
      title: 'Nuevo usuario',
      icon: LucideIcons.userPlus,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) => Validators.required(v, fieldName: 'El nombre'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Email'),
              validator: Validators.email,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Contraseña temporal'),
              validator: Validators.password,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _role,
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
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _groupId,
              dropdownColor: colors.surface,
              decoration: const InputDecoration(labelText: 'Equipo (opcional)'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Sin equipo')),
                for (final group in catalog.groups)
                  DropdownMenuItem<String?>(value: group.id, child: Text(group.name)),
              ],
              onChanged: (v) => setState(() => _groupId = v),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSearchField extends StatelessWidget {
  const _UserSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextField(
      controller: controller,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Buscar',
        hintText: 'Nombre o correo',
        prefixIcon: Icon(LucideIcons.search, color: colors.primary, size: 18),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(LucideIcons.xCircle, size: 16),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
      onChanged: onChanged,
    );
  }
}

class _GroupFilterDropdown extends StatelessWidget {
  const _GroupFilterDropdown({
    required this.groups,
    required this.value,
    required this.onChanged,
  });

  final List<GroupModel> groups;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Equipo',
        prefixIcon: Icon(LucideIcons.users, color: colors.primary, size: 18),
      ),
      dropdownColor: colors.surface,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
        const DropdownMenuItem<String?>(
          value: AppFilterValues.noGroup,
          child: Text('Sin equipo'),
        ),
        for (final g in groups) DropdownMenuItem<String?>(value: g.id, child: Text(g.name)),
      ],
      onChanged: onChanged,
    );
  }
}

class _RoleFilterDropdown extends StatelessWidget {
  const _RoleFilterDropdown({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: 'Rol',
        prefixIcon: Icon(LucideIcons.shield, color: colors.primary, size: 18),
      ),
      dropdownColor: colors.surface,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
        DropdownMenuItem<String?>(
          value: AppRoles.superAdmin,
          child: Text(AuthService.roleLabel(AppRoles.superAdmin)),
        ),
        DropdownMenuItem<String?>(
          value: AppRoles.trabajadorNormal,
          child: Text(AuthService.roleLabel(AppRoles.trabajadorNormal)),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Nombre + Correo, then Rol/Grupo/Estado tags in their own row below —
/// separated instead of crammed into one ListTile row/trailing, and with a
/// real profile photo instead of a generic icon.
class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.groupName, required this.onTap});

  final AppUser user;
  final String? groupName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatarDisplay(user: user, size: 44, borderWidth: 1.5),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        user.email,
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Tag(label: AuthService.roleLabel(user.role)),
                _Tag(label: groupName ?? 'Sin equipo', muted: groupName == null),
                _StatusBadge(isActive: user.isActive),
              ],
            ),
          ],
        ),
      ),
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
  const _Tag({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = muted ? colors.textSecondary : colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10)),
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
                      UserAvatarDisplay(user: user, size: 44, borderWidth: 1.5),
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
                  Text('Equipo', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedGroupId,
                    dropdownColor: colors.surface,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Sin equipo')),
                      for (final group in catalog.groups)
                        DropdownMenuItem<String?>(value: group.id, child: Text(group.name)),
                    ],
                    onChanged: (value) async {
                      if (value == selectedGroupId) return;
                      try {
                        await userRepo.updateGroup(user.id, value);
                        setState(() => selectedGroupId = value);
                        if (sheetContext.mounted) {
                          SnackbarUtils.showSuccess(sheetContext, 'Equipo actualizado');
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
                      decoration: const InputDecoration(labelText: 'Equipo (opcional)'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Sin equipo')),
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
