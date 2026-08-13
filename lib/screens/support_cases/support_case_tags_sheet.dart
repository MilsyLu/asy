import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/support_case_tag_model.dart';
import '../../services/support_case_repository.dart';
import '../../widgets/confirm_dialog.dart';

/// "Gestionar etiquetas" — only reachable by someone with
/// `manageSupportCases` (gated by the caller, see `support_cases_page.dart`).
/// The catalog itself is what firestore.rules calls "administrado": anyone
/// can read/apply these tags to a case, only this screen can add or
/// remove entries.
class SupportCaseTagsSheet extends StatefulWidget {
  const SupportCaseTagsSheet({super.key});

  @override
  State<SupportCaseTagsSheet> createState() => _SupportCaseTagsSheetState();
}

class _SupportCaseTagsSheetState extends State<SupportCaseTagsSheet> {
  final _nameController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final repo = context.read<SupportCaseRepository>();
    setState(() => _isSaving = true);
    try {
      await repo.addTag(name);
      _nameController.clear();
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete(SupportCaseTagModel tag) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Eliminar etiqueta',
      message: '¿Eliminar la etiqueta "${tag.name}"? Los casos que ya la tienen la conservan '
          'como texto — solo deja de estar disponible para elegirla en casos nuevos.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    final repo = context.read<SupportCaseRepository>();
    try {
      await repo.deleteTag(tag.id);
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final repo = context.watch<SupportCaseRepository>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gestionar etiquetas',
                style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'Cualquiera puede aplicarlas a un caso; solo un administrador puede crearlas o eliminarlas.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: const InputDecoration(isDense: true, labelText: 'Nueva etiqueta'),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSaving ? null : _add,
                  icon: _isSaving
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.plus, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: StreamBuilder<List<SupportCaseTagModel>>(
                stream: repo.watchTags(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    );
                  }
                  final tags = snapshot.data!;
                  if (tags.isEmpty) {
                    return Text('Sin etiquetas todavía.', style: TextStyle(color: colors.textSecondary, fontSize: 12));
                  }
                  return SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in tags)
                          Chip(
                            label: Text(tag.name),
                            onDeleted: () => _delete(tag),
                            deleteIcon: const Icon(LucideIcons.x, size: 14),
                          ),
                      ],
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
