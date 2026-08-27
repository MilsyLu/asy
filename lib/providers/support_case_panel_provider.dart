import 'package:flutter/foundation.dart';

/// Qué muestra el panel derecho de Casos de Soporte.
///
/// Vive fuera de la página porque el botón "Nuevo caso" está en la barra
/// superior del shell, que no puede llamar al `setState` de la pantalla. Es el
/// mismo camino que el selector de periodo del Dashboard: en vez de que la
/// barra empuje algo hacia la página, las dos leen el mismo estado.
///
/// Sólo aplica al diseño con barra lateral. En celular no hay espacio para dos
/// columnas, así que el detalle se abre como pantalla completa y el formulario
/// como hoja, sin pasar por aquí.
class SupportCasePanelController extends ChangeNotifier {
  String? _caseId;
  bool _creating = false;

  /// Caso abierto en el panel, o null.
  String? get caseId => _caseId;

  /// Si el panel muestra el formulario de caso nuevo.
  bool get creating => _creating;

  /// Si hay algo que mostrar — lo que decide si la pantalla se parte en dos.
  bool get isOpen => _caseId != null || _creating;

  void openCase(String id) {
    if (_caseId == id && !_creating) return;
    _caseId = id;
    _creating = false;
    notifyListeners();
  }

  /// El formulario reemplaza al detalle en vez de apilarse: son dos usos del
  /// mismo espacio, y tener los dos abiertos a la vez no significa nada.
  void openCreate() {
    if (_creating) return;
    _caseId = null;
    _creating = true;
    notifyListeners();
  }

  void close() {
    if (!isOpen) return;
    _caseId = null;
    _creating = false;
    notifyListeners();
  }
}
