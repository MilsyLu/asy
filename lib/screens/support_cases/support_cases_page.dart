import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/support_case_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/support_case_model.dart';
import '../../models/support_case_tag_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/support_case_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/responsive_sheet.dart';
import '../../widgets/support_case_badges.dart';
import 'support_case_detail_view.dart';
import 'support_case_kanban_view.dart';
import 'support_case_tags_sheet.dart';

enum _ViewMode { tabla, kanban }

enum _QuickFilter {
  todos,
  pendientes,
  enProceso,
  esperandoCliente,
  resueltos,
  altaPrioridad,
  mas5dias,
  mas10dias,
  misCasos,
}

extension on _QuickFilter {
  String get label {
    switch (this) {
      case _QuickFilter.todos:
        return 'Todos';
      case _QuickFilter.pendientes:
        return 'Pendientes';
      case _QuickFilter.enProceso:
        return 'En proceso';
      case _QuickFilter.esperandoCliente:
        return 'Esperando cliente';
      case _QuickFilter.resueltos:
        return 'Resueltos';
      case _QuickFilter.altaPrioridad:
        return 'Alta prioridad';
      case _QuickFilter.mas5dias:
        return 'Más de 5 días';
      case _QuickFilter.mas10dias:
        return 'Más de 10 días';
      case _QuickFilter.misCasos:
        return 'Mis casos';
    }
  }

  bool matches(SupportCaseModel c, String? myUid) {
    switch (this) {
      case _QuickFilter.todos:
        return true;
      // "Pendientes" == recién creado, todavía sin tocar (estado "Nuevo").
      case _QuickFilter.pendientes:
        return c.status == SupportCaseStatus.nuevo;
      case _QuickFilter.enProceso:
        return c.status == SupportCaseStatus.enProceso;
      case _QuickFilter.esperandoCliente:
        return c.status == SupportCaseStatus.esperandoCliente;
      case _QuickFilter.resueltos:
        return !SupportCaseStatus.isOpen(c.status);
      case _QuickFilter.altaPrioridad:
        return c.priority == SupportCasePriority.alta || c.priority == SupportCasePriority.critica;
      case _QuickFilter.mas5dias:
        return SupportCaseStatus.isOpen(c.status) && c.daysOpen() > 5;
      case _QuickFilter.mas10dias:
        return SupportCaseStatus.isOpen(c.status) && c.daysOpen() > 10;
      case _QuickFilter.misCasos:
        return myUid != null && (c.assignedUserId == myUid || c.createdBy == myUid);
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
  _SortBy _sortBy = _SortBy.recientes;
  _ViewMode _viewMode = _ViewMode.tabla;
  String? _selectedCaseId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SupportCaseModel> _applyFiltersAndSort(List<SupportCaseModel> all, String? myUid) {
    final q = _query.trim().toLowerCase();
    var result = all.where((c) => _filter.matches(c, myUid)).toList();
    if (q.isNotEmpty) {
      result = result.where((c) {
        return c.clientName.toLowerCase().contains(q) ||
            c.contactName.toLowerCase().contains(q) ||
            c.subject.toLowerCase().contains(q) ||
            c.description.toLowerCase().contains(q) ||
            c.status.toLowerCase().contains(q) ||
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
            (a, b) => (_priorityRank[b.priority] ?? -1).compareTo(_priorityRank[a.priority] ?? -1));
        break;
      case _SortBy.dias:
        result.sort((a, b) => b.daysOpen().compareTo(a.daysOpen()));
        break;
    }
    return result;
  }

  void _openCreateForm(BuildContext context) {
    showResponsiveSheet<void>(
      context,
      desktopMaxWidth: 480,
      contentBuilder: (sheetCtx) => _NewCaseForm(onCreated: () => Navigator.of(sheetCtx).pop()),
    );
  }

  void _openManageTags(BuildContext context) {
    showResponsiveSheet<void>(
      context,
      desktopMaxWidth: 420,
      contentBuilder: (_) => const SupportCaseTagsSheet(),
    );
  }

  void _openDetail(BuildContext context, String caseId) {
    if (context.isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SupportCaseDetailView(caseId: caseId, showAppBar: true)),
      );
    } else {
      setState(() => _selectedCaseId = caseId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SupportCaseRepository>();
    final auth = context.watch<AuthProvider>();
    final myUid = auth.appUser?.id;
    final isMobile = context.isMobile;

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
        final filtered = _applyFiltersAndSort(all, myUid);

        final canDelete = auth.hasPermission(AppPermissions.manageSupportCases);
        final list = (!isMobile && _viewMode == _ViewMode.kanban)
            ? SupportCaseKanbanView(cases: filtered, onTap: (id) => _openDetail(context, id))
            : _CaseList(
                cases: filtered,
                selectedCaseId: _selectedCaseId,
                onTap: (id) => _openDetail(context, id),
                canDelete: canDelete,
              );

        final header = _CasesHeader(
          all: all,
          searchController: _searchController,
          onQueryChanged: (v) => setState(() => _query = v),
          filter: _filter,
          onFilterChanged: (f) => setState(() => _filter = f),
          sortBy: _sortBy,
          onSortChanged: (s) => setState(() => _sortBy = s),
          onNewCase: isMobile ? null : () => _openCreateForm(context),
          onManageTags: canDelete ? () => _openManageTags(context) : null,
          viewMode: isMobile ? null : _viewMode,
          onViewModeChanged: (v) => setState(() => _viewMode = v),
        );

        if (isMobile) {
          return Column(children: [header, Expanded(child: list)]);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 900 && _selectedCaseId != null;
            final listColumn = Column(children: [header, Expanded(child: list)]);
            if (!sideBySide) return listColumn;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: listColumn),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: SupportCaseDetailView(
                    key: ValueKey(_selectedCaseId),
                    caseId: _selectedCaseId!,
                    showAppBar: false,
                    onClose: () => setState(() => _selectedCaseId = null),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (!widget.showAppBar) return Scaffold(body: body, floatingActionButton: fab);
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
    required this.sortBy,
    required this.onSortChanged,
    required this.onNewCase,
    required this.onManageTags,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final List<SupportCaseModel> all;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final _QuickFilter filter;
  final ValueChanged<_QuickFilter> onFilterChanged;
  final _SortBy sortBy;
  final ValueChanged<_SortBy> onSortChanged;
  final VoidCallback? onNewCase;

  /// Null when the viewer lacks `manageSupportCases` — hides the button.
  final VoidCallback? onManageTags;

  /// Null on mobile — hides the Tabla/Kanban toggle (Kanban's 5 columns
  /// don't fit a phone screen).
  final _ViewMode? viewMode;
  final ValueChanged<_ViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final today = DateTime.now();
    final open = all.where((c) => SupportCaseStatus.isOpen(c.status));
    final urgentes = open.where(
        (c) => c.priority == SupportCasePriority.alta || c.priority == SupportCasePriority.critica);
    final mas5 = open.where((c) => c.daysOpen() > 5);
    final mas10 = open.where((c) => c.daysOpen() > 10);
    final resueltosHoy = all.where((c) =>
        c.resolvedAt != null &&
        c.resolvedAt!.year == today.year &&
        c.resolvedAt!.month == today.month &&
        c.resolvedAt!.day == today.day);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Casos de Soporte',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              if (onManageTags != null)
                IconButton(
                  tooltip: 'Gestionar etiquetas',
                  onPressed: onManageTags,
                  icon: Icon(LucideIcons.tag, color: colors.primary, size: 20),
                ),
              if (onNewCase != null)
                ElevatedButton.icon(
                  onPressed: onNewCase,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Nuevo caso'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _KpiCard(icon: LucideIcons.fileText, label: 'Casos abiertos', value: open.length, color: colors.primary),
              _KpiCard(icon: LucideIcons.alertTriangle, label: 'Urgentes', value: urgentes.length, color: Colors.red),
              _KpiCard(icon: LucideIcons.sunrise, label: 'Más de 5 días', value: mas5.length, color: Colors.orange),
              _KpiCard(icon: LucideIcons.alarmClock, label: 'Más de 10 días', value: mas10.length, color: Colors.red),
              _KpiCard(icon: LucideIcons.checkCircle2, label: 'Resueltos hoy', value: resueltosHoy.length, color: Colors.green),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Buscar por cliente, asunto, descripción o número de caso',
                    prefixIcon: Icon(LucideIcons.search, color: colors.primary, size: 18),
                  ),
                  onChanged: onQueryChanged,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<_SortBy>(
                value: sortBy,
                underline: const SizedBox.shrink(),
                onChanged: (v) => v != null ? onSortChanged(v) : null,
                items: const [
                  DropdownMenuItem(value: _SortBy.recientes, child: Text('Más recientes')),
                  DropdownMenuItem(value: _SortBy.antiguos, child: Text('Más antiguos')),
                  DropdownMenuItem(value: _SortBy.prioridad, child: Text('Prioridad')),
                  DropdownMenuItem(value: _SortBy.dias, child: Text('Días sin resolver')),
                ],
              ),
              if (viewMode != null) ...[
                const SizedBox(width: 8),
                SegmentedButton<_ViewMode>(
                  segments: const [
                    ButtonSegment(value: _ViewMode.tabla, label: Text('Tabla'), icon: Icon(LucideIcons.list, size: 15)),
                    ButtonSegment(
                        value: _ViewMode.kanban, label: Text('Kanban'), icon: Icon(LucideIcons.columns, size: 15)),
                  ],
                  selected: {viewMode!},
                  onSelectionChanged: (s) => onViewModeChanged(s.first),
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _QuickFilter.values) ...[
                  _FilterChip(
                    label: f.label,
                    selected: filter == f,
                    onTap: () => onFilterChanged(f),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.icon, required this.label, required this.value, required this.color});

  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 148,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$value', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? colors.primary : colors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? colors.onPrimary : colors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
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
Future<void> confirmDeleteSupportCase(BuildContext context, SupportCaseModel c) async {
  final confirm = await showConfirmDialog(
    context,
    title: 'Eliminar caso',
    message: '¿Eliminar el caso CS-${c.caseNumber.toString().padLeft(4, '0')} '
        '(${c.clientName}) de forma permanente? Esta acción no se puede deshacer.',
    confirmLabel: 'Eliminar',
    destructive: true,
  );
  if (!confirm || !context.mounted) return;
  try {
    await context.read<SupportCaseRepository>().delete(c.id);
    if (context.mounted) SnackbarUtils.showSuccess(context, 'Caso eliminado');
  } catch (e) {
    if (context.mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
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
        return _CaseRow(
          caseModel: c,
          selected: c.id == selectedCaseId,
          onTap: () => onTap(c.id),
          onDelete: canDelete ? () => confirmDeleteSupportCase(context, c) : null,
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
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.08) : colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? colors.primary : priorityColor.withValues(alpha: 0.25)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
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
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: avatarColor.withValues(alpha: 0.85),
                            child: Text(
                              _initialsFor(c.clientName),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
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
                                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
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
                                    style: TextStyle(color: colors.textSecondary.withValues(alpha: 0.8), fontSize: 11),
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
                            Text(formattedDate, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
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
}

// ---------------------------------------------------------------------------
// Create form
// ---------------------------------------------------------------------------

class _NewCaseForm extends StatefulWidget {
  const _NewCaseForm({required this.onCreated});

  final VoidCallback onCreated;

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

  @override
  void dispose() {
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
    setState(() => _isSaving = true);
    try {
      await repo.createCase(
        clientName: _clientController.text.trim(),
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
      if (mounted) {
        SnackbarUtils.showSuccess(context, 'Caso creado');
        widget.onCreated();
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nuevo caso', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _clientController,
                autofocus: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(labelText: 'Cliente *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'El cliente es obligatorio' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactController,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(labelText: 'Persona que reportó (opcional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(labelText: 'Teléfono (opcional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectController,
                style: TextStyle(color: colors.textPrimary),
                decoration: const InputDecoration(labelText: 'Asunto *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'El asunto es obligatorio' : null,
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
                        for (final p in SupportCasePriority.all) DropdownMenuItem(value: p, child: Text(p)),
                      ],
                      onChanged: (v) => setState(() => _priority = v ?? _priority),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _pickReportedDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Fecha de reporte'),
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
              DropdownButtonFormField<String?>(
                initialValue: _assignedUserId,
                decoration: const InputDecoration(labelText: 'Responsable (opcional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Sin asignar')),
                  for (final u in catalog.users) DropdownMenuItem<String?>(value: u.id, child: Text(u.name)),
                ],
                onChanged: (v) => setState(() => _assignedUserId = v),
              ),
              const SizedBox(height: 16),
              Text('Etiquetas', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              const SizedBox(height: 6),
              StreamBuilder<List<SupportCaseTagModel>>(
                stream: context.read<SupportCaseRepository>().watchTags(),
                builder: (context, snapshot) {
                  final tags = snapshot.data ?? const [];
                  if (tags.isEmpty) {
                    return Text(
                      'Sin etiquetas todavía.',
                      style: TextStyle(color: colors.textSecondary, fontSize: 12),
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
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
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
