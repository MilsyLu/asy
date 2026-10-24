import 'package:flutter/material.dart';
import '../core/theme/theme_colors.dart';

class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colors.primary),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: TextStyle(color: colors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

/// Simple empty-state placeholder used across list screens.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colors.primary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lo que se muestra cuando un `StreamBuilder` recibe un error.
///
/// Existe porque sin ella el error no se ve: el patrón de toda la app es
/// `if (!snapshot.hasData) return const LoadingIndicator();`, y un stream que
/// falla nunca entrega datos, así que la pantalla se queda girando para
/// siempre. Pasó con Requerimientos — faltaba un índice de Firestore y el
/// módulo nuevo parecía colgado, sin una sola pista de por qué.
///
/// Un índice que falta es el caso típico, y el mensaje de Firestore trae el
/// enlace para crearlo, así que se muestra tal cual en vez de resumirlo.
class StreamErrorState extends StatelessWidget {
  const StreamErrorState({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colors.error),
            const SizedBox(height: 14),
            Text(
              'No se pudieron cargar los datos.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SelectableText(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
