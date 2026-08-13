import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/app_user.dart';
import '../../models/group_model.dart';
import '../../models/system_config_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/catalog_repository.dart';
import '../../services/user_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/side_panel_shell.dart';

/// Admin: CRUD for `groups` ("Equipos" in the UI — display text only, the
/// collection/fields stay `groups`/`groupId` everywhere), plus
/// assigning/unassigning member users.
class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key, this.showAppBar = true});

  /// Set to false when this page lives inside the main shell's [IndexedStack]
  /// so the outer shell's AppBar is used instead of rendering a second one.
  final bool showAppBar;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  /// Tablet/desktop only: which the always-visible right panel is showing.
  /// `null` → "Nuevo equipo" form. Non-null → member checklist for that team.
  GroupModel? _membersTarget;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final auth = context.watch<AuthProvider>();
    final isMobile = context.isMobile;
    final isSuperAdmin = auth.isSuperAdmin;
    final canEditTeams = auth.hasPermission(AppPermissions.manageTeams);
    final query = _query.trim().toLowerCase();
    // A scoped admin_equipo only ever sees the teams they manage.
    final visibleGroups =
        isSuperAdmin ? catalog.groups : catalog.groups.where((g) => auth.managesGroup(g.id)).toList();
    final groups = query.isEmpty
        ? visibleGroups
        : visibleGroups.where((g) => g.name.toLowerCase().contains(query)).toList();

    // If the team currently open in the members panel got deleted (or
    // filtered out isn't relevant here — only real deletion matters) from
    // under us, fall back to the create form instead of a stale reference.
    if (_membersTarget != null &&
        !catalog.groups.any((g) => g.id == _membersTarget!.id)) {
      _membersTarget = null;
    }

    final searchField = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          labelText: 'Buscar',
          hintText: 'Nombre del equipo',
          prefixIcon: Icon(LucideIcons.search, color: context.colors.primary, size: 18),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(LucideIcons.xCircle, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
        ),
        onChanged: (v) => setState(() => _query = v),
      ),
    );

    Widget buildList({required bool shrink}) {
      if (groups.isEmpty) {
        return EmptyState(
          message: query.isEmpty
              ? 'No hay equipos creados todavía.'
              : 'Ningún equipo coincide con "$query".',
          icon: LucideIcons.users,
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shrinkWrap: shrink,
        physics: shrink ? const NeverScrollableScrollPhysics() : null,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final group = groups[index];
          final members = catalog.usersInGroup(group.id);
          // Tablet/desktop: name/description editable right on the card,
          // Miembros swaps the right panel instead of opening a dialog.
          // Mobile keeps the "Editar"/"Miembros" dialogs and the FAB.
          // A scoped admin_equipo (even with manageTeams) never manages
          // team membership here — that's Usuarios' job, scoped correctly
          // per-worker there; this page only lets them edit name/
          // description/timeSelectionMode for their own teams.
          return isMobile
              ? _GroupCard(
                  group: group,
                  members: members,
                  canEdit: isSuperAdmin || canEditTeams,
                  canManageMembers: isSuperAdmin,
                )
              : _TeamCardEditable(
                  group: group,
                  members: members,
                  canEdit: isSuperAdmin || canEditTeams,
                  onEditMembers:
                      isSuperAdmin ? () => setState(() => _membersTarget = group) : null,
                );
        },
      );
    }

    Widget body;
    if (isMobile) {
      body = Column(children: [searchField, Expanded(child: buildList(shrink: false))]);
    } else if (!isSuperAdmin && !canEditTeams) {
      // A scoped admin without manageTeams never creates/deletes teams or
      // manages membership from here, so there's no right panel to show —
      // just the (already filtered-to-their-teams) list.
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidthWide),
          child: Column(
            children: [searchField, Expanded(child: buildList(shrink: false))],
          ),
        ),
      );
    } else {
      // The right panel needs real width to stay legible (it's a form/a
      // member checklist, not a sidebar label) — below ~900px of actual
      // available width, keeping it beside the list squeezes the row-cards
      // into unreadable single-letter columns. Below that threshold, stack
      // the panel under the list instead, both full width, rather than
      // relying on device category alone (a collapsed vs. expanded sidebar
      // changes the real available width just as much as screen size does).
      body = LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 900;
          final panel = _membersTarget == null
              ? const _CreateTeamPanel(key: ValueKey('create'))
              : _MembersPanel(
                  key: ValueKey(_membersTarget!.id),
                  group: _membersTarget!,
                  onDone: () => setState(() => _membersTarget = null),
                );

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
                        children: [searchField, Expanded(child: buildList(shrink: false))],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 16, 16),
                  // Scrollable: a tall panel (e.g. a team with many members
                  // to check off) can exceed the available height, leaving
                  // the confirm button unreachable without this.
                  child: SizedBox(width: 320, child: SingleChildScrollView(child: panel)),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                buildList(shrink: true),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: panel,
                ),
              ],
            ),
          );
        },
      );
    }

    // Tablet/desktop: the panel replaces the FAB for creating a team, so no
    // FAB there. Mobile keeps it (no persistent panel to hold the form).
    // Team creation is super_admin-only, plus a scoped admin_equipo with
    // manageTeams (who becomes that team's manager automatically — see
    // _CreateTeamPanel._save()).
    final fab = isMobile && (isSuperAdmin || canEditTeams)
        ? FloatingActionButton(
            onPressed: () => _showGroupFormDialog(context),
            child: const Icon(LucideIcons.plus),
          )
        : null;
    if (!widget.showAppBar) return Scaffold(body: body, floatingActionButton: fab);
    return Scaffold(
      appBar: AppBar(title: const Text('Equipos')),
      body: body,
      floatingActionButton: fab,
    );
  }
}

/// Tablet/desktop always-visible right panel, default state: create a new
/// team. Stays in place (fields just clear) after a successful save, so an
/// admin can add several teams in a row without reopening anything.
class _CreateTeamPanel extends StatefulWidget {
  const _CreateTeamPanel({super.key});

  @override
  State<_CreateTeamPanel> createState() => _CreateTeamPanelState();
}

class _CreateTeamPanelState extends State<_CreateTeamPanel> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final isSuperAdmin = context.read<AuthProvider>().isSuperAdmin;
    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    try {
      if (isSuperAdmin) {
        await context.read<CatalogRepository>().addGroup(name, description);
      } else {
        // A scoped admin_equipo (with manageTeams) can't write to `groups`
        // directly — firestore.rules keeps that create-only-by-super_admin.
        // This Cloud Function does it server-side AND adds the new team to
        // the caller's own managedGroupIds in the same atomic step, so they
        // immediately administer the team they just created.
        await FirebaseFunctions.instance
            .httpsCallable('createTeamAsScopedAdmin')
            .call<Map<String, dynamic>>({'name': name, 'description': description});
      }
      if (mounted) {
        _nameController.clear();
        _descController.clear();
        SnackbarUtils.showSuccess(context, 'Equipo creado');
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) SnackbarUtils.showError(context, e.message ?? 'No se pudo crear el equipo');
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SidePanelShell(
      title: 'Nuevo equipo',
      icon: LucideIcons.plus,
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
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descController,
              maxLines: 2,
              style: TextStyle(color: colors.textPrimary),
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
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
                  : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tablet/desktop always-visible right panel, member-editing state: replaces
/// the create form while active. `onDone` (Guardar or Cancelar) returns the
/// panel to the create form.
class _MembersPanel extends StatefulWidget {
  const _MembersPanel({super.key, required this.group, required this.onDone});

  final GroupModel group;
  final VoidCallback onDone;

  @override
  State<_MembersPanel> createState() => _MembersPanelState();
}

class _MembersPanelState extends State<_MembersPanel> {
  late final Set<String> _selected;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final catalog = context.read<CatalogProvider>();
    _selected = {
      for (final u in catalog.users)
        if (u.isInGroup(widget.group.id)) u.id,
    };
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final catalog = context.read<CatalogProvider>();
    final userRepo = context.read<UserRepository>();
    try {
      for (final user in catalog.users) {
        final shouldBeMember = _selected.contains(user.id);
        final isMember = user.isInGroup(widget.group.id);
        if (shouldBeMember && !isMember) {
          await userRepo.addToGroup(user.id, widget.group.id);
        } else if (!shouldBeMember && isMember) {
          await userRepo.removeFromGroup(user.id, widget.group.id);
        }
      }
      if (mounted) {
        SnackbarUtils.showSuccess(context, 'Miembros actualizados');
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    final allUsers = List<AppUser>.from(catalog.users)
      ..sort((a, b) => a.name.compareTo(b.name));

    return SidePanelShell(
      title: 'Miembros de "${widget.group.name}"',
      icon: LucideIcons.userCheck,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allUsers.isEmpty)
            Text(
              'No hay usuarios registrados.',
              style: TextStyle(color: colors.textSecondary),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: allUsers.length,
                itemBuilder: (context, index) {
                  final user = allUsers[index];
                  final otherGroupIds =
                      user.groupIds.where((id) => id != widget.group.id).toList();
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(user.id),
                    title: Text(
                      user.name,
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    ),
                    subtitle: Text(
                      otherGroupIds.isNotEmpty
                          ? '${user.email} · también en "${catalog.groupNames(otherGroupIds)}"'
                          : user.email,
                      style: TextStyle(color: colors.textSecondary, fontSize: 11),
                    ),
                    activeColor: colors.primary,
                    checkColor: colors.background,
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selected.add(user.id);
                        } else {
                          _selected.remove(user.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : widget.onDone,
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared card chrome for the right panel (title + icon header, bordered
/// container) so the create and members states look like one consistent
/// panel, not two different UIs swapping in and out.

/// Tablet/desktop team card: Nombre and Descripción are real [TextField]s
/// that save on blur (when the field loses focus) instead of requiring the
/// "Editar" dialog mobile uses. Miembros and Eliminar stay as explicit
/// actions — this is only for the two plain-text fields.
class _TeamCardEditable extends StatefulWidget {
  const _TeamCardEditable({
    required this.group,
    required this.members,
    required this.canEdit,
    required this.onEditMembers,
  });

  final GroupModel group;
  final List<AppUser> members;

  /// Whether name/description/timeSelectionMode may be edited — true for
  /// super_admin, or a scoped admin_equipo with manageTeams on this team.
  final bool canEdit;

  /// Null hides the Miembros edit action entirely — membership is only
  /// manageable by super_admin from this page (a scoped admin manages
  /// membership per-worker from Usuarios instead).
  final VoidCallback? onEditMembers;

  @override
  State<_TeamCardEditable> createState() => _TeamCardEditableState();
}

class _TeamCardEditableState extends State<_TeamCardEditable> {
  late final _nameController = TextEditingController(text: widget.group.name);
  late final _descController =
      TextEditingController(text: widget.group.description);
  final _nameFocus = FocusNode();
  final _descFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_onNameFocusChange);
    _descFocus.addListener(_onDescFocusChange);
  }

  @override
  void didUpdateWidget(covariant _TeamCardEditable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect remote changes (e.g. edited in another tab/session) as long as
    // the user isn't actively typing in that field right now.
    if (!_nameFocus.hasFocus && _nameController.text != widget.group.name) {
      _nameController.text = widget.group.name;
    }
    if (!_descFocus.hasFocus &&
        _descController.text != widget.group.description) {
      _descController.text = widget.group.description;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _nameFocus.dispose();
    _descFocus.dispose();
    super.dispose();
  }

  void _onNameFocusChange() {
    if (_nameFocus.hasFocus) return;
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      _nameController.text = widget.group.name; // name is required — revert
      return;
    }
    if (newName == widget.group.name) return;
    _save(newName, _descController.text.trim());
  }

  void _onDescFocusChange() {
    if (_descFocus.hasFocus) return;
    final newDesc = _descController.text.trim();
    if (newDesc == widget.group.description) return;
    _save(_nameController.text.trim(), newDesc);
  }

  Future<void> _save(String name, String description, {String? timeSelectionMode}) async {
    final repo = context.read<CatalogRepository>();
    try {
      await repo.updateGroup(widget.group.id, name, description,
          timeSelectionMode: timeSelectionMode);
      if (mounted) SnackbarUtils.showSuccess(context, 'Equipo actualizado');
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      }
    }
  }

  Future<void> _saveTimeSelectionMode(String mode) => _save(
        _nameController.text.trim(),
        _descController.text.trim(),
        timeSelectionMode: mode,
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final memberCount = widget.members.length;
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _FieldColumn(
                  label: 'Nombre',
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    enabled: widget.canEdit,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(isDense: true),
                    onSubmitted: (_) => _nameFocus.unfocus(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _FieldColumn(
                  label: 'Descripción',
                  child: TextField(
                    controller: _descController,
                    focusNode: _descFocus,
                    enabled: widget.canEdit,
                    minLines: 1,
                    maxLines: 2,
                    style: TextStyle(color: colors.textPrimary, fontSize: 14),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Opcional',
                    ),
                    onSubmitted: (_) => _descFocus.unfocus(),
                  ),
                ),
              ),
              if (widget.onEditMembers != null) ...[
                const SizedBox(width: 16),
                _FieldColumn(
                  label: memberCount == 1 ? 'Miembros (1)' : 'Miembros ($memberCount)',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: widget.onEditMembers,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.pencil, size: 14, color: colors.success),
                          const SizedBox(width: 4),
                          Text(
                            'Editar',
                            style: TextStyle(
                              color: colors.success,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (widget.onEditMembers != null) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: TextButton.icon(
                    onPressed: () => _deleteGroup(context, widget.group),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: const Text('Eliminar'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _FieldColumn(
            label: 'Selección de hora',
            child: _TimeSelectionModeToggle(
              mode: widget.group.timeSelectionMode,
              enabled: widget.canEdit,
              onChanged: _saveTimeSelectionMode,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "Libre" / "Según horarios configurados" toggle — replaces the old
/// single global systemConfig setting, now one per team.
class _TimeSelectionModeToggle extends StatelessWidget {
  const _TimeSelectionModeToggle({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final String mode;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        ChoiceChip(
          label: const Text('Según horarios configurados'),
          selected: mode == SystemConfigModel.modeCatalog,
          onSelected: enabled ? (_) => onChanged(SystemConfigModel.modeCatalog) : null,
        ),
        ChoiceChip(
          label: const Text('Libre'),
          selected: mode == SystemConfigModel.modeFree,
          onSelected: enabled ? (_) => onChanged(SystemConfigModel.modeFree) : null,
        ),
      ],
    );
  }
}

/// Small column header ("Nombre", "Descripción", "Miembros (N)") above its
/// field/action — matches the table-like layout the user asked for instead
/// of relying on hint text alone to say what each box is.
class _FieldColumn extends StatelessWidget {
  const _FieldColumn({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.members,
    required this.canEdit,
    required this.canManageMembers,
  });

  final GroupModel group;
  final List<AppUser> members;
  final bool canEdit;
  final bool canManageMembers;

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
          _TimeSelectionModeToggle(
            mode: group.timeSelectionMode,
            enabled: canEdit,
            onChanged: (mode) => context
                .read<CatalogRepository>()
                .updateGroup(group.id, group.name, group.description, timeSelectionMode: mode),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              if (canManageMembers)
                TextButton.icon(
                  onPressed: () => _showMembersDialog(context, group),
                  icon: const Icon(LucideIcons.userCheck, size: 16),
                  label: const Text('Miembros'),
                ),
              if (canEdit)
                TextButton.icon(
                  onPressed: () => _showGroupFormDialog(context, existing: group),
                  icon: const Icon(LucideIcons.pencil, size: 16),
                  label: const Text('Editar'),
                ),
              if (canManageMembers)
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
  final isSuperAdmin = context.read<AuthProvider>().isSuperAdmin;
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
            title: Text(existing == null ? 'Nuevo equipo' : 'Editar equipo'),
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
                            if (isSuperAdmin) {
                              await repo.addGroup(
                                nameController.text.trim(),
                                descriptionController.text.trim(),
                              );
                            } else {
                              // See _CreateTeamPanel._save() — a scoped
                              // admin_equipo creates a team via this Cloud
                              // Function, which also adds it to their own
                              // managedGroupIds in the same step.
                              await FirebaseFunctions.instance
                                  .httpsCallable('createTeamAsScopedAdmin')
                                  .call<Map<String, dynamic>>({
                                'name': nameController.text.trim(),
                                'description': descriptionController.text.trim(),
                              });
                            }
                          } else {
                            await repo.updateGroup(
                              existing.id,
                              nameController.text.trim(),
                              descriptionController.text.trim(),
                            );
                          }
                          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                        } on FirebaseFunctionsException catch (e) {
                          if (dialogContext.mounted) {
                            SnackbarUtils.showError(
                                dialogContext, e.message ?? 'No se pudo crear el equipo');
                          }
                          setState(() => isSaving = false);
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
    title: 'Eliminar equipo',
    message:
        '¿Eliminar el equipo "${group.name}"? Los usuarios asignados quedarán sin equipo.',
    confirmLabel: 'Eliminar',
    destructive: true,
  );
  if (!confirm) return;
  if (!context.mounted) return;

  final catalogRepo = context.read<CatalogRepository>();
  final userRepo = context.read<UserRepository>();
  final catalog = context.read<CatalogProvider>();
  try {
    final members = catalog.usersInGroup(group.id);
    for (final member in members) {
      await userRepo.removeFromGroup(member.id, group.id);
    }
    await catalogRepo.deleteGroup(group.id);
    if (context.mounted) {
      SnackbarUtils.showSuccess(context, 'Equipo eliminado');
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
      if (u.isInGroup(group.id)) u.id,
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
                        final otherGroupIds =
                            user.groupIds.where((id) => id != group.id).toList();
                        return CheckboxListTile(
                          value: selected.contains(user.id),
                          title: Text(user.name, style: TextStyle(color: colors.textPrimary)),
                          subtitle: Text(
                            otherGroupIds.isNotEmpty
                                ? '${user.email} · también en "${catalog.groupNames(otherGroupIds)}"'
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
                            final isMember = user.isInGroup(group.id);
                            if (shouldBeMember && !isMember) {
                              await userRepo.addToGroup(user.id, group.id);
                            } else if (!shouldBeMember && isMember) {
                              await userRepo.removeFromGroup(user.id, group.id);
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
