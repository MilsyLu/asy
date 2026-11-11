import 'package:flutter/foundation.dart';

/// Por quién están filtradas las tareas que se ven: Calendario y Agenda.
///
/// Uno solo para las cuatro vistas —Mes, Semana, Encargados y la Agenda
/// diaria— y no uno por pantalla: quien está revisando lo que asignó no
/// quiere volver a elegirse a sí mismo cada vez que cambia de vista. Es la
/// misma pregunta mirada desde distintos ángulos.
///
/// **No se guarda entre sesiones, a propósito.** Un filtro que sobrevive al
/// cierre del navegador hace que al día siguiente la agenda aparezca medio
/// vacía y nadie recuerde por qué: se lee como "no hay tareas", que es la
/// peor manera de equivocarse. Al entrar siempre se ve todo.
///
/// Reportes tiene su propio filtro y no comparte éste: allá uno arma una
/// consulta puntual, y que se le pegara el filtro de la agenda sería lo
/// contrario de lo que espera.
class FiltroAutorProvider extends ChangeNotifier {
  String? _autor;

  /// La clave de autor elegida (ver `autor_tarea.dart`), o null para todos.
  String? get autor => _autor;

  bool get activo => _autor != null;

  void cambiar(String? clave) {
    if (_autor == clave) return;
    _autor = clave;
    notifyListeners();
  }

  void limpiar() => cambiar(null);
}
