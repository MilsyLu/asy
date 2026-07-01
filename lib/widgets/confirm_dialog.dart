import 'package:flutter/material.dart';
import '../core/responsive/app_spacing.dart';
import '../core/responsive/responsive.dart';
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
  final insetPadding = _dialogInsetPadding(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      insetPadding: insetPadding,
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        ElevatedButton(
          style: destructive
              ? ElevatedButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: confirmForegroundColor ?? colors.textPrimary,
                )
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
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
  final insetPadding = _dialogInsetPadding(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      insetPadding: insetPadding,
      title: Text(title),
      content: Text(message),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(acknowledgeLabel),
        ),
      ],
    ),
  );
}

/// Computes [AlertDialog.insetPadding] so dialogs are width-capped on tablet
/// and desktop while remaining unchanged on mobile.
EdgeInsets _dialogInsetPadding(BuildContext context) {
  final screenW = Responsive.screenWidth(context);
  if (context.isDesktop) {
    final h = ((screenW - AppLayout.dialogWidthDesktop) / 2)
        .clamp(24.0, double.infinity);
    return EdgeInsets.symmetric(horizontal: h, vertical: 24);
  }
  if (context.isTablet) {
    final h = ((screenW - AppLayout.dialogWidthTablet) / 2)
        .clamp(24.0, double.infinity);
    return EdgeInsets.symmetric(horizontal: h, vertical: 24);
  }
  return const EdgeInsets.symmetric(horizontal: 40, vertical: 24);
}
