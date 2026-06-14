import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/app_user.dart';
import '../../models/group_model.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../services/user_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';

/// Admin: CRUD for `groups`, plus assigning/unassigning member users.
class GroupsPage extends StatelessWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final groups = catalog.groups;

    return Scaffold(
      appBar: AppBar(title: const Text('Grupos')),
      body: groups.isEmpty
          ? const EmptyState(
              message: 'No hay grupos creados todavía.',
              icon: LucideIcons.users,
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final group = groups[index];
                final members = catalog.usersInGroup(group.id);
                return _GroupCard(group: group, members: members);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGroupFormDialog(context),
        child: const Icon(LucideIcons.plus),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.members});

  final GroupModel group;
  final List<AppUser> members;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
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
              Icon(LucideIcons.users, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  group.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${members.length} ${members.length == 1 ? 'miembro' : 'miembros'}',
                  style: TextStyle(color: colors.primary, fontSize: 11),
                ),
              ),
            ],
          ),
          if (group.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              group.description,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _showMembersDialog(context, group),
                icon: const Icon(LucideIcons.userCheck, size: 16),
                label: const Text('Miembros'),
              ),
              TextButton.icon(
                onPressed: () => _showGroupFormDialog(context, existing: group),
                icon: const Icon(LucideIcons.pencil, size: 16),
                label: const Text('Editar'),
              ),
              TextButton.icon(
                onPressed: () => _deleteGroup(context, group),
                style: TextButton.styleFrom(foregroundColor: colors.error),
                icon: const Icon(LucideIcons.trash2, size: 16),
                label: const Text('Eliminar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showGroupFormDialog(BuildContext context, {GroupModel? existing}) async {
  final colors = context.colors;
  final repo = context.read<CatalogRepository>();
  final nameController = TextEditingController(text: existing?.name ?? '');
  final descriptionController = TextEditingController(text: existing?.description ?? '');
  final formKey = GlobalKey<FormState>();
  bool isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: Text(existing == null ? 'Nuevo grupo' : 'Editar grupo'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descriptionController,
                    maxLines: 2,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                  ),
                ],
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
                          if (existing == null) {
                            await repo.addGroup(
                              nameController.text.trim(),
                              descriptionController.text.trim(),
                            );
                          } else {
                            await repo.updateGroup(
                              existing.id,
                              nameController.text.trim(),
                              descriptionController.text.trim(),
                            );
                          }
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
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
                    : const Text('Guardar'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _deleteGroup(BuildContext context, GroupModel group) async {
  final confirm = await showConfirmDialog(
    context,
    title: 'Eliminar grupo',
    message:
        '¿Eliminar el grupo "${group.name}"? Los usuarios asignados quedarán sin grupo.',
    confirmLabel: 'Eliminar',
    destructive: true,
  );
  if (!confirm) return;
  if (!context.mounted) return;

  final catalogRepo = context.read<CatalogRepository>();
  final userRepo = context.read<UserRepository>();
  try {
    final members = await userRepo.getUsersByGroup(group.id);
    for (final member in members) {
      await userRepo.updateGroup(member.id, null);
    }
    await catalogRepo.deleteGroup(group.id);
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Grupo eliminado');
    }
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }
}

Future<void> _showMembersDialog(BuildContext context, GroupModel group) async {
  final colors = context.colors;
  final catalog = context.read<CatalogProvider>();
  final userRepo = context.read<UserRepository>();
  final allUsers = List<AppUser>.from(catalog.users)
    ..sort((a, b) => a.name.compareTo(b.name));

  final selected = <String>{
    for (final u in allUsers)
      if (u.groupId == group.id) u.id,
  };
  bool isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setState) {
          return AlertDialog(
            title: Text('Miembros de "${group.name}"'),
            content: SizedBox(
              width: double.maxFinite,
              child: allUsers.isEmpty
                  ? Text(
                      'No hay usuarios registrados.',
                      style: TextStyle(color: colors.textSecondary),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: allUsers.length,
                      itemBuilder: (context, index) {
                        final user = allUsers[index];
                        final isInOtherGroup =
                            user.groupId != null && user.groupId != group.id;
                        return CheckboxListTile(
                          value: selected.contains(user.id),
                          title: Text(user.name, style: TextStyle(color: colors.textPrimary)),
                          subtitle: Text(
                            isInOtherGroup
                                ? '${user.email} · en "${catalog.groupName(user.groupId)}"'
                                : user.email,
                            style: TextStyle(color: colors.textSecondary, fontSize: 12),
                          ),
                          activeColor: colors.primary,
                          checkColor: colors.background,
                          onChanged: (checked) {
                            setState(() {
                              if (checked == true) {
                                selected.add(user.id);
                              } else {
                                selected.remove(user.id);
                              }
                            });
                          },
                        );
                      },
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
                        setState(() => isSaving = true);
                        try {
                          for (final user in allUsers) {
                            final shouldBeMember = selected.contains(user.id);
                            final isMember = user.groupId == group.id;
                            if (shouldBeMember && !isMember) {
                              await userRepo.updateGroup(user.id, group.id);
                            } else if (!shouldBeMember && isMember) {
                              await userRepo.updateGroup(user.id, null);
                            }
                          }
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
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
                    : const Text('Guardar'),
              ),
            ],
          );
        },
      );
    },
  );
}
