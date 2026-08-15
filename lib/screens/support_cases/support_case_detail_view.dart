import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/support_case_constants.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/support_case_history_entry.dart';
import '../../models/support_case_model.dart';
import '../../models/support_case_tag_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/storage_service.dart';
import '../../services/support_case_repository.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/support_case_badges.dart';

/// Case detail: editable estado/prioridad/responsable, the original
/// (never-edited) description, attachments, and the timeline built from
/// `supportCases/{id}/history` — plus the comment box that appends to it.
/// Used both as a right-side panel (desktop/tablet, [showAppBar]=false) and
/// as a full page (mobile, pushed via [Navigator]).
class SupportCaseDetailView extends StatefulWidget {
  const SupportCaseDetailView({
    super.key,
    required this.caseId,
    this.showAppBar = true,
    this.onClose,
  });

  final String caseId;
  final bool showAppBar;
  final VoidCallback? onClose;

  @override
  State<SupportCaseDetailView> createState() => _SupportCaseDetailViewState();
}

class _SupportCaseDetailViewState extends State<SupportCaseDetailView> {
  final _commentController = TextEditingController();
  bool _isSendingComment = false;
  bool _isUploading = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _sendComment(SupportCaseModel c) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final user = context.read<AuthProvider>().appUser;
    if (user == null) return;
    setState(() => _isSendingComment = true);
    try {
      await context
          .read<SupportCaseRepository>()
          .addComment(c.id, text, authorId: user.id, authorName: user.name);
      _commentController.clear();
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSendingComment = false);
    }
  }

  Future<void> _pickAndUploadAttachment(SupportCaseModel c) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    final user = context.read<AuthProvider>().appUser;
    if (user == null) return;
    final repo = context.read<SupportCaseRepository>();
    setState(() => _isUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await StorageService.uploadSupportCaseAttachment(
        empresaId: c.empresaId,
        caseId: c.id,
        bytes: bytes,
        fileName: picked.name,
        contentType: 'image/jpeg',
      );
      await repo.addAttachment(
            c.id,
            SupportCaseAttachment(
              url: url,
              name: picked.name,
              contentType: 'image/jpeg',
              size: bytes.length,
            ),
            authorId: user.id,
            authorName: user.name,
          );
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'No se pudo subir el archivo.');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _changeStatus(SupportCaseModel c, String newStatus) async {
    final user = context.read<AuthProvider>().appUser;
    if (user == null || newStatus == c.status) return;
    try {
      await context
          .read<SupportCaseRepository>()
          .updateStatus(c.id, newStatus, authorId: user.id, authorName: user.name);
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  Future<void> _changePriority(SupportCaseModel c, String newPriority) async {
    final user = context.read<AuthProvider>().appUser;
    if (user == null || newPriority == c.priority) return;
    try {
      await context
          .read<SupportCaseRepository>()
          .updatePriority(c.id, newPriority, authorId: user.id, authorName: user.name);
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  Future<void> _changeAssignee(SupportCaseModel c, String? newAssigneeId, String? newAssigneeName) async {
    final user = context.read<AuthProvider>().appUser;
    if (user == null || newAssigneeId == c.assignedUserId) return;
    try {
      await context.read<SupportCaseRepository>().updateAssignee(
            c.id,
            newAssigneeId,
            newAssigneeName,
            authorId: user.id,
            authorName: user.name,
          );
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  Future<void> _editTags(SupportCaseModel c) async {
    final repo = context.read<SupportCaseRepository>();
    final user = context.read<AuthProvider>().appUser;
    if (user == null) return;
    List<SupportCaseTagModel> available;
    try {
      available = await repo.watchTags().first;
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
      return;
    }
    if (!mounted) return;
    final selected = {...c.tags};
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Etiquetas'),
          content: SizedBox(
            width: 360,
            child: available.isEmpty
                ? const Text('Todavía no hay etiquetas creadas.')
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in available)
                        FilterChip(
                          label: Text(tag.name),
                          selected: selected.contains(tag.name),
                          onSelected: (v) => setState(() {
                            if (v) {
                              selected.add(tag.name);
                            } else {
                              selected.remove(tag.name);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await repo.updateTags(c.id, result.toList(), authorId: user.id, authorName: user.name);
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  Future<void> _editReminder(SupportCaseModel c) async {
    final repo = context.read<SupportCaseRepository>();
    final user = context.read<AuthProvider>().appUser;
    if (user == null) return;

    final now = DateTime.now();
    final initialDate = c.reminderTime ?? now.add(const Duration(days: 1));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(now) ? now : initialDate,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Fecha del recordatorio',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: c.reminderTime != null
          ? TimeOfDay.fromDateTime(c.reminderTime!)
          : TimeOfDay.fromDateTime(now),
      helpText: 'Hora del recordatorio',
    );
    if (pickedTime == null || !mounted) return;

    final reminderTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final noteController = TextEditingController(text: c.reminderNote);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recordatorio'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Nota (opcional)',
              hintText: 'Ej: consultarle al equipo de tecno',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await repo.setReminder(
        c.id,
        reminderTime: reminderTime,
        reminderNote: noteController.text.trim(),
        authorId: user.id,
        authorName: user.name,
      );
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  Future<void> _clearReminder(SupportCaseModel c) async {
    final user = context.read<AuthProvider>().appUser;
    if (user == null) return;
    try {
      await context.read<SupportCaseRepository>().setReminder(
            c.id,
            reminderTime: null,
            authorId: user.id,
            authorName: user.name,
          );
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  Future<void> _confirmDelete(SupportCaseModel c) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar caso',
      message: '¿Eliminar el caso CS-${c.caseNumber.toString().padLeft(4, '0')} de forma '
          'permanente? Esta acción no se puede deshacer.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    try {
      await context.read<SupportCaseRepository>().delete(c.id);
      if (widget.showAppBar && mounted) Navigator.of(context).pop();
      widget.onClose?.call();
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<SupportCaseRepository>();
    final auth = context.watch<AuthProvider>();
    final canDelete = auth.hasPermission(AppPermissions.manageSupportCases);

    final body = StreamBuilder<SupportCaseModel?>(
      stream: repo.watchCase(widget.caseId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LoadingIndicator();
        final c = snapshot.data;
        if (c == null) {
          return const EmptyState(message: 'Este caso ya no existe.', icon: LucideIcons.alertCircle);
        }
        return _buildContent(context, c, canDelete);
      },
    );

    if (!widget.showAppBar) return body;
    return Scaffold(appBar: AppBar(title: const Text('Detalle del caso')), body: body);
  }

  Widget _buildContent(BuildContext context, SupportCaseModel c, bool canDelete) {
    final colors = context.colors;
    final catalog = context.watch<CatalogProvider>();
    final isResolved = !SupportCaseStatus.isOpen(c.status);

    Widget sectionLabel(String text) =>
        Text(text, style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600));

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: colors.primary.withValues(alpha: 0.15),
                      child: Icon(LucideIcons.fileText, color: colors.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'CS-${c.caseNumber.toString().padLeft(4, '0')} · ${c.clientName}',
                            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          if (c.contactName.isNotEmpty || c.contactPhone.isNotEmpty)
                            Text(
                              [c.contactName, c.contactPhone].where((s) => s.isNotEmpty).join(' · '),
                              style: TextStyle(color: colors.textSecondary, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    if (canDelete)
                      IconButton(
                        tooltip: 'Eliminar',
                        icon: Icon(LucideIcons.trash2, color: colors.error, size: 18),
                        onPressed: () => _confirmDelete(c),
                      ),
                    if (widget.onClose != null)
                      IconButton(
                        tooltip: 'Cerrar',
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Reportado: ${AppDateUtils.formatShortDate(c.reportedAt)}',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                    Text('· Registrado: ${AppDateUtils.formatShortDate(c.createdAt)}',
                        style: TextStyle(color: colors.textSecondary.withValues(alpha: 0.7), fontSize: 11)),
                    PopupMenuButton<String>(
                      initialValue: c.status,
                      onSelected: (v) => _changeStatus(c, v),
                      itemBuilder: (_) =>
                          [for (final s in SupportCaseStatus.all) PopupMenuItem(value: s, child: Text(s))],
                      child: StatusBadge(status: c.status),
                    ),
                    PopupMenuButton<String>(
                      initialValue: c.priority,
                      onSelected: (v) => _changePriority(c, v),
                      itemBuilder: (_) =>
                          [for (final p in SupportCasePriority.all) PopupMenuItem(value: p, child: Text(p))],
                      child: PriorityBadge(priority: c.priority),
                    ),
                    DaysOpenBadge(days: c.daysOpen(), resolved: isResolved),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(LucideIcons.userCircle, size: 14, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Text('Responsable:', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                    const SizedBox(width: 6),
                    DropdownButton<String?>(
                      value: c.assignedUserId,
                      underline: const SizedBox.shrink(),
                      hint: Text('Sin asignar', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Sin asignar')),
                        for (final u in catalog.users)
                          DropdownMenuItem<String?>(value: u.id, child: Text(u.name)),
                      ],
                      onChanged: (v) => _changeAssignee(c, v, v == null ? null : catalog.userName(v)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.bellRing, size: 14, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: c.reminderTime == null
                          ? TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _editReminder(c),
                              child: const Text('Programar recordatorio'),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recordatorio: ${AppDateUtils.formatShortDate(c.reminderTime!)} '
                                  '${AppDateUtils.formatTime12h(c.reminderTime!)}',
                                  style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (c.reminderNote.isNotEmpty)
                                  Text(
                                    c.reminderNote,
                                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                                  ),
                                Row(
                                  children: [
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () => _editReminder(c),
                                      child: const Text('Editar', style: TextStyle(fontSize: 12)),
                                    ),
                                    const SizedBox(width: 12),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: colors.error,
                                        padding: EdgeInsets.zero,
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () => _clearReminder(c),
                                      child: const Text('Quitar', style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                sectionLabel('ASUNTO'),
                const SizedBox(height: 4),
                Text(c.subject, style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                const SizedBox(height: 14),
                sectionLabel('DESCRIPCIÓN'),
                const SizedBox(height: 4),
                Text(
                  c.description.isEmpty ? '—' : c.description,
                  style: TextStyle(color: colors.textPrimary, fontSize: 14),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    sectionLabel('ETIQUETAS'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _editTags(c),
                      icon: const Icon(LucideIcons.tag, size: 15),
                      label: const Text('Etiquetar'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (c.tags.isEmpty)
                  Text('Sin etiquetas.', style: TextStyle(color: colors.textSecondary, fontSize: 12))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final tag in c.tags) Chip(label: Text(tag), visualDensity: VisualDensity.compact)],
                  ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    sectionLabel('ARCHIVOS ADJUNTOS'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _isUploading ? null : () => _pickAndUploadAttachment(c),
                      icon: _isUploading
                          ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(LucideIcons.paperclip, size: 15),
                      label: const Text('Adjuntar'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (c.attachments.isEmpty)
                  Text('Sin adjuntos.', style: TextStyle(color: colors.textSecondary, fontSize: 12))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final a in c.attachments)
                        _AttachmentChip(attachment: a, onOpen: () => launchUrl(Uri.parse(a.url))),
                    ],
                  ),
                const SizedBox(height: 20),
                sectionLabel('LÍNEA DE TIEMPO'),
                const SizedBox(height: 8),
                _Timeline(caseId: c.id),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: colors.divider),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Escribe un comentario...',
                  ),
                  onSubmitted: (_) => _sendComment(c),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSendingComment ? null : () => _sendComment(c),
                child: _isSendingComment
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Comentar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onOpen});

  final SupportCaseAttachment attachment;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.image, size: 14, color: colors.primary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.caseId});

  final String caseId;

  IconData _iconFor(String type) {
    switch (type) {
      case SupportCaseHistoryType.created:
        return LucideIcons.plusCircle;
      case SupportCaseHistoryType.statusChanged:
        return LucideIcons.refreshCw;
      case SupportCaseHistoryType.priorityChanged:
        return LucideIcons.alertTriangle;
      case SupportCaseHistoryType.assigneeChanged:
        return LucideIcons.userCircle;
      case SupportCaseHistoryType.attachmentAdded:
        return LucideIcons.paperclip;
      default:
        return LucideIcons.messageSquare;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return StreamBuilder<List<SupportCaseHistoryEntry>>(
      stream: context.read<SupportCaseRepository>().watchHistory(caseId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final entries = snapshot.data!;
        if (entries.isEmpty) {
          return Text('Sin actividad todavía.', style: TextStyle(color: colors.textSecondary, fontSize: 12));
        }
        return Column(
          children: [
            for (final e in entries.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration:
                          BoxDecoration(color: colors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(_iconFor(e.type), size: 12, color: colors.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.text, style: TextStyle(color: colors.textPrimary, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            '${e.authorName} · ${AppDateUtils.formatDateTimeOrDash(e.createdAt)}',
                            style: TextStyle(color: colors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
