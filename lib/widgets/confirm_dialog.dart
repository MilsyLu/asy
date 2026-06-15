import 'package:flutter/material.dart';
import '../core/theme/theme_colors.dart';

/// Shows a gold-themed confirmation dialog. Returns true if the user
/// confirmed, false/null otherwise.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  String cancelLabel = 'Cancelar',
  bool destructive = false,
  Color? confirmForegroundColor,
}) async {
  final colors = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: confirmForegroundColor ?? colors.textPrimary,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows a gold-themed informational dialog with a single acknowledgement
/// button. Unlike [showConfirmDialog], there is no "cancel" path — it only
/// informs the user, who can then continue with whatever action triggered it.
Future<void> showInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  String acknowledgeLabel = 'Continuar',
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(acknowledgeLabel),
        ),
      ],
    ),
  );
}
