import 'package:firebase_core/firebase_core.dart';
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
    _show(
      context,
      message: message,
      icon: Icons.error_outline,
      colorOf: (c) => c.error,
    );
  }

  static void showSuccess(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.check_circle_outline,
      colorOf: (c) => c.success,
    );
  }

  static void showInfo(BuildContext context, String message) {
    _show(
      context,
      message: message,
      icon: Icons.info_outline,
      colorOf: (c) => c.primary,
    );
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        message,
                        style: TextStyle(color: colors.textPrimary),
                      ),
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

  /// Maps an error to a friendly Spanish message.
  ///
  /// When the code has no wording of its own, the message still carries the
  /// raw code. The previous version collapsed everything it did not
  /// recognise into a flat "ocurrió un error inesperado", and since it only
  /// knew *sign-in* codes, that was almost everything: a Storage rejection
  /// and a Firestore missing-index both surfaced as the same sentence. That
  /// is how a broken attachment upload stayed invisible for two weeks.
  /// Showing the code costs the user nothing and turns "no anda" into
  /// something answerable.
  static String firebaseErrorMessage(Object error) {
    final code = _errorCode(error);
    final friendly = _friendlyMessage(code, error.toString());
    if (friendly != null) return friendly;

    final label = _errorLabel(error, code);
    return label == null
        ? 'Ocurrió un error inesperado. Intenta nuevamente'
        : 'Ocurrió un error inesperado ($label). Intenta nuevamente';
  }

  /// The bare code (`permission-denied`, `unauthorized`, …), whether the
  /// error is a real [FirebaseException] or something that merely printed one
  /// — plugins and `Future` wrappers often hand over a plain string.
  static String? _errorCode(Object error) {
    if (error is FirebaseException) return error.code;
    final match = RegExp(
      r'\[([a-z_]+)/([a-z0-9\-]+)\]',
    ).firstMatch(error.toString());
    return match?.group(2);
  }

  /// `firebase_storage/unauthorized` when the plugin is known, else the code.
  static String? _errorLabel(Object error, String? code) {
    if (error is FirebaseException) return '${error.plugin}/${error.code}';
    final match = RegExp(
      r'\[([a-z_]+)/([a-z0-9\-]+)\]',
    ).firstMatch(error.toString());
    if (match != null) return '${match.group(1)}/${match.group(2)}';
    return code;
  }

  /// Wording for the failures a user can actually do something about.
  /// [raw] keeps the old substring behaviour working for errors that never
  /// expose a parseable code.
  static String? _friendlyMessage(String? code, String raw) {
    bool is_(String c) => code == c || raw.contains(c);

    // ── Sesión ────────────────────────────────────────────────────────────
    if (is_('user-not-found') ||
        is_('wrong-password') ||
        is_('invalid-credential')) {
      return 'Email o contraseña incorrectos';
    }
    if (is_('invalid-email')) return 'El formato del email no es válido';
    if (is_('user-disabled')) return 'Esta cuenta ha sido deshabilitada';
    if (is_('too-many-requests')) {
      return 'Demasiados intentos. Intenta más tarde';
    }
    if (is_('email-already-in-use')) return 'Ese email ya está registrado';
    if (is_('weak-password')) return 'La contraseña es demasiado débil';
    if (is_('requires-recent-login')) {
      return 'Debes iniciar sesión nuevamente para continuar';
    }

    // ── Ingreso con Google ────────────────────────────────────────────────
    // These three are configuration faults, not user mistakes, so the wording
    // points at the administrator instead of asking the user to try again —
    // retrying will fail identically until somebody changes a setting.
    if (is_('operation-not-allowed')) {
      return 'El ingreso con Google no está habilitado. Avisa al administrador';
    }
    if (is_('unauthorized-domain')) {
      return 'Este sitio no está autorizado para ingresar con Google. '
          'Avisa al administrador';
    }
    if (is_('popup-blocked')) {
      return 'El navegador bloqueó la ventana de Google. Permite las ventanas '
          'emergentes para este sitio e intenta de nuevo';
    }
    if (is_('account-exists-with-different-credential')) {
      return 'Ese correo ya tiene una cuenta en CheCu con contraseña. '
          'Ingresa con tu correo y contraseña';
    }

    // ── Conexión ──────────────────────────────────────────────────────────
    if (is_('network-request-failed') ||
        is_('unavailable') ||
        is_('retry-limit-exceeded')) {
      return 'Error de conexión. Revisa tu internet';
    }
    if (is_('deadline-exceeded')) {
      return 'La operación tardó demasiado. Intenta de nuevo';
    }

    // ── Permisos (Firestore dice permission-denied, Storage unauthorized) ──
    if (is_('permission-denied') || is_('unauthorized')) {
      return 'No tienes permisos para realizar esta acción';
    }
    if (is_('unauthenticated')) {
      return 'Tu sesión expiró. Inicia sesión nuevamente';
    }

    // ── Datos ─────────────────────────────────────────────────────────────
    if (is_('not-found') || is_('object-not-found')) {
      return 'No se encontró lo que buscabas';
    }
    if (is_('already-exists')) return 'Ese registro ya existe';
    if (is_('failed-precondition')) {
      // En Firestore esto casi siempre es un índice compuesto que falta —
      // invisible para el usuario y difícil de adivinar sin el texto.
      return 'La consulta no se pudo completar. Avisa al administrador';
    }

    // ── Almacenamiento ────────────────────────────────────────────────────
    if (is_('quota-exceeded')) return 'Se agotó el espacio de almacenamiento';
    if (is_('canceled')) return 'La operación fue cancelada';

    return null;
  }
}
