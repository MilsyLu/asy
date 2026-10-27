import 'package:flutter/material.dart';

/// Letra un 12 % más pequeña y campos más bajos para los formularios de la
/// columna derecha en escritorio ("Nueva tarea", "Nuevo cliente"…).
///
/// Esos paneles miden 320–360 px de ancho y comparten el alto con otras
/// tarjetas: con la letra normal pedían barra de desplazamiento y las
/// etiquetas se cortaban ("Encarg…", "Tipo de tarea (…"). Michel pidió letra
/// más pequeña ahí; el resto de la app queda igual.
class CompactPanelScope extends StatelessWidget {
  const CompactPanelScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(0.88),
      ),
      child: Theme(
        data: theme.copyWith(
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        child: child,
      ),
    );
  }
}
