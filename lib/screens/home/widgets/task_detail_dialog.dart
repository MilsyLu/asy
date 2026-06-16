import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../models/task_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/catalog_provider.dart';
import '../../../services/task_repository.dart';
import '../../../widgets/confirm_dialog.dart';
import '../add_edit_task_page.dart';
import 'reschedule_dialog.dart';

/// Read-only dialog with the full details of [task]: client, phone
/// (highlighted, with a copy-to-clipboard button), type, date, hour,
/// assignee, group and observations.
Future<void> showTaskDetailDialog(BuildContext context, TaskModel task) {
  final catalog = context.read<CatalogProvider>();
  final auth = context.read<AuthProvider>();
  final repo = context.read<TaskRepository>();
  final formattedPhone = Validators.formatPhone(task.clientPhone);

  final isPending = task.statusId == catalog.pendingStatusId;
  final isCompleted = task.statusId == catalog.completedStatusId;
  final canEdit = auth.isSuperAdmin || isPending;
  final canComplete = !isCompleted;
  final canReschedule = !isCompleted;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final colors = dialogContext.colors;
      return AlertDialog(
        title: const Text('Detalle de la tarea'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                icon: LucideIcons.userCircle,
                label: 'Cliente',
                value: task.clientName,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.phone, size: 18, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Teléfono',
                            style: TextStyle(color: colors.textSecondary, fontSize: 11),
                          ),
                          Text(
                            formattedPhone.isEmpty ? 'Sin teléfono' : formattedPhone,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (formattedPhone.isNotEmpty)
                      _CopyPhoneButton(phone: Validators.cleanPhone(task.clientPhone)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: LucideIcons.tag,
                label: 'Tipo',
                value: catalog.taskTypeName(task.taskTypeId),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: LucideIcons.calendar,
                label: 'Fecha',
                value: AppDateUtils.formatShortDate(AppDateUtils.parseDateKey(task.date)),
              ),
              const SizedBox(height: 12),
              _DetailRow(icon: LucideIcons.clock, label: 'Hora', value: task.hour),
              const SizedBox(height: 12),
              _DetailRow(
                icon: LucideIcons.userCheck,
                label: 'Encargado',
                value: catalog.userName(task.assignedUserId),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: LucideIcons.users,
                label: 'Grupo',
                value: catalog.groupName(task.groupId),
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: LucideIcons.fileText,
                label: 'Observaciones',
                value: task.observations.isEmpty ? 'Sin observaciones' : task.observations,
              ),
              if (canEdit || canComplete || canReschedule) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: [
                    if (canEdit)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AddEditTaskPage(existingTask: task),
                            ),
                          );
                        },
                        icon: const Icon(LucideIcons.pencil, size: 16),
                        label: const Text('Editar'),
                      ),
                    if (canReschedule)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          showRescheduleDialog(context, task);
                        },
                        icon: const Icon(LucideIcons.repeat, size: 16),
                        label: const Text('Reprogramar'),
                      ),
                    if (canComplete)
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: colors.success),
                        onPressed: () async {
                          Navigator.of(dialogContext).pop();
                          final completedId = catalog.completedStatusId;
                          if (completedId == null) {
                            if (context.mounted) {
                              SnackbarUtils.showError(
                                  context, 'No existe un estado "Completada" configurado');
                            }
                            return;
                          }
                          final confirm = await showConfirmDialog(
                            context,
                            title: 'Completar tarea',
                            message:
                                '¿Marcar la tarea de ${task.clientName} a las ${task.hour} como completada?',
                            confirmLabel: 'Completar',
                          );
                          if (!confirm) return;
                          try {
                            await repo.completeTask(task.id, completedId);
                            if (context.mounted) {
                              SnackbarUtils.showSuccess(context, 'Tarea completada');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              SnackbarUtils.showError(
                                  context, SnackbarUtils.firebaseErrorMessage(e));
                            }
                          }
                        },
                        icon: const Icon(LucideIcons.checkCircle, size: 16),
                        label: const Text('Completar'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Copy-to-clipboard button for [phone]. On tap, copies the number and
/// temporarily swaps its icon from "copy" to "check" for ~2 seconds while
/// showing a top banner confirmation (see [_showCopiedBanner]).
class _CopyPhoneButton extends StatefulWidget {
  const _CopyPhoneButton({required this.phone});

  final String phone;

  @override
  State<_CopyPhoneButton> createState() => _CopyPhoneButtonState();
}

class _CopyPhoneButtonState extends State<_CopyPhoneButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.phone));
    if (!mounted) return;
    setState(() => _copied = true);
    _showCopiedBanner(context);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      tooltip: 'Copiar número',
      icon: Icon(
        _copied ? LucideIcons.check : LucideIcons.copy,
        size: 18,
        color: _copied ? colors.success : colors.primary,
      ),
      onPressed: _copy,
    );
  }
}

/// Shows a floating confirmation banner ("Número copiado") above the
/// current dialog by inserting an [OverlayEntry] into the root [Overlay],
/// which renders above the dialog's modal barrier. Auto-dismisses after
/// ~2 seconds.
void _showCopiedBanner(BuildContext context) {
  final colors = context.colors;
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => Positioned(
      top: MediaQuery.of(overlayContext).padding.top + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.success,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.checkCircle2, color: Colors.white, size: 18),
              SizedBox(width: 10),
              Text('Número copiado', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  Future.delayed(const Duration(seconds: 2), () => entry.remove());
}
