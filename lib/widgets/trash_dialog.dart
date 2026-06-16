import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/theme_colors.dart';

/// Confirmation dialog before soft-deleting a task.
/// Returns true if the user confirms, false otherwise.
Future<bool> showSendToTrashDialog(BuildContext context) async {
  final colors = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Row(
          children: [
            Icon(LucideIcons.trash2, size: 20, color: colors.error),
            const SizedBox(width: 10),
            const Text('Enviar a papelera'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Esta tarea dejará de aparecer en:'),
            const SizedBox(height: 10),
            for (final item in ['Inicio', 'Calendario', 'Semana', 'Reportes'])
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 8),
                child: Text(
                  '• $item',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Podrá restaurarse posteriormente desde la papelera.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Enviar'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
