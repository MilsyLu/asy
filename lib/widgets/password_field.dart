import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme/theme_colors.dart';

/// Un campo de contraseña con el ojito para verla.
///
/// Existe porque sin él uno escribe a ciegas y se entera del dedazo cuando la
/// otra persona no puede entrar — que es exactamente lo que pasó con la clave
/// de Verónica. El de Iniciar sesión ya tenía el ojito; los de crear usuario
/// y crear empresa no, y son justo donde se escribe una contraseña que va a
/// usar alguien más.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.labelText = 'Contraseña',
    this.hintText,
    this.validator,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool autofocus;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _oculta = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextFormField(
      controller: widget.controller,
      obscureText: _oculta,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      validator: widget.validator,
      style: TextStyle(color: colors.textPrimary),
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon: Icon(LucideIcons.lock, color: colors.primary),
        suffixIcon: IconButton(
          tooltip: _oculta ? 'Mostrar contraseña' : 'Ocultar contraseña',
          icon: Icon(
            _oculta ? LucideIcons.eye : LucideIcons.eyeOff,
            size: 18,
            color: colors.textSecondary,
          ),
          onPressed: () => setState(() => _oculta = !_oculta),
        ),
      ),
    );
  }
}
