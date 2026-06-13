import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Helpers for showing user-friendly feedback instead of raw exceptions.
class SnackbarUtils {
  SnackbarUtils._();

  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppColors.success),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  static void showInfo(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
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
