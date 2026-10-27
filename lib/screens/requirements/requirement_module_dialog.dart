import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/utils/snackbar_utils.dart';
import '../../providers/catalog_provider.dart';

/// El valor que marca "agregar un módulo nuevo" dentro de un desplegable.
///
/// Una cadena que nadie escribiría como nombre de módulo: si alguna vez
/// coincidiera, el desplegable confundiría un módulo real con el botón.
const String kAgregarModulo = '\u0000agregar-modulo';

/// La última opción de un desplegable de módulos: "Agregar módulo…".
///
/// Va de última y separada por una línea para que no se lea como un módulo
/// más de la lista.
DropdownMenuItem<String> agregarModuloItem(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return DropdownMenuItem<String>(
    value: kAgregarModulo,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.plus, size: 15, color: colors.primary),
        const SizedBox(width: 6),
        Text(
          'Agregar módulo…',
          style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// Pregunta el nombre y lo guarda. Devuelve el módulo creado, o null.
///
/// Los módulos no son una lista cerrada: VinApp le agrega partes nuevas cada
/// tanto —Domicilios no existía hace un año— y hasta ahora eso significaba
/// esperar a que alguien tocara el código. Los que venían en la hoja siguen
/// en [RequirementModule.all]; esto agrega encima, por empresa.
Future<String?> pedirModuloNuevo(BuildContext context) async {
  final controlador = TextEditingController();
  final catalogo = context.read<CatalogProvider>();

  final nombre = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nuevo módulo'),
      content: TextField(
        controller: controlador,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Nombre del módulo',
          hintText: 'Reservas, Fidelización, Propinas…',
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controlador.text.trim()),
          child: const Text('Agregar'),
        ),
      ],
    ),
  );
  controlador.dispose();

  if (nombre == null || nombre.isEmpty) return null;

  // Ya existe: se elige el que hay en vez de crear un duplicado que después
  // parte en dos los requerimientos de la misma parte del producto.
  final yaEsta = catalogo.requirementModules.firstWhere(
    (m) => m.toLowerCase() == nombre.toLowerCase(),
    orElse: () => '',
  );
  if (yaEsta.isNotEmpty) {
    if (context.mounted) {
      SnackbarUtils.showInfo(context, 'Ese módulo ya existe.');
    }
    return yaEsta;
  }

  try {
    await catalogo.addRequirementModule(nombre);
    return nombre;
  } catch (e) {
    if (context.mounted) {
      SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    }
    return null;
  }
}
