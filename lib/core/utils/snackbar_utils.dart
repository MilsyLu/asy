import 'package:flutter/material.dart';
import '../theme/theme_colors.dart';

/// Helpers for showing user-friendly feedback instead of raw exceptions.
///
/// Shows a floating banner pinned near the top of the screen (below the
/// status bar / any AppBar) instead of Flutter's default bottom [SnackBar].
/// On wide tablet/desktop layouts a bottom SnackBar could land on top of
/// list content near the bottom of the viewport — the top banner never
/// overlaps content below it.
class SnackbarUtils {
  SnackbarUtils._();

  static OverlayEntry? _currentEntry;

  static void showError(BuildContext context, String message) {
    _show(context, message: message, icon: Icons.error_outline, colorOf: (c) => c.error);
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message: message, icon: Icons.check_circle_outline, colorOf: (c) => c.success);
  }

  static void showInfo(BuildContext context, String message) {
    _show(context, message: message, icon: Icons.info_outline, colorOf: (c) => c.primary);
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color Function(AppColorsExtension) colorOf,
  }) {
    final colors = context.colors;
    final color = colorOf(colors);

    // Replace whatever banner is currently showing instead of stacking them.
    _currentEntry?.remove();
    _currentEntry = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        top: MediaQuery.of(overlayContext).padding.top + 12,
        left: 16,
        right: 16,
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(message, style: TextStyle(color: colors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _currentEntry = entry;
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentEntry == entry) {
        entry.remove();
        _currentEntry = null;
      }
    });
  }

  /// Maps common Firebase error codes to friendly Spanish messages.
  static String firebaseErrorMessage(Object error) {
    final message = error.toString();
    if (message.contains('user-not-found') ||
        message.contains('wrong-password') ||
        message.contains('invalid-credential')) {
      return 'Email o contraseña incorrectos';
    }
    if (message.contains('invalid-email')) {
      return 'El formato del email no es válido';
    }
    if (message.contains('user-disabled')) {
      return 'Esta cuenta ha sido deshabilitada';
    }
    if (message.contains('too-many-requests')) {
      return 'Demasiados intentos. Intenta más tarde';
    }
    if (message.contains('network-request-failed')) {
      return 'Error de conexión. Revisa tu internet';
    }
    if (message.contains('email-already-in-use')) {
      return 'Ese email ya está registrado';
    }
    if (message.contains('requires-recent-login')) {
      return 'Debes iniciar sesión nuevamente para continuar';
    }
    if (message.contains('permission-denied')) {
      return 'No tienes permisos para realizar esta acción';
    }
    return 'Ocurrió un error inesperado. Intenta nuevamente';
  }
}
