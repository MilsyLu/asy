/// Quién asignó una tarea, incluyendo los dos casos en que no fue nadie.
///
/// De las tareas que hay hoy en CheCu, más de la mitad no dicen quién las
/// asignó: unas nacieron antes de que se guardara el dato y otras entran
/// por el puente de Google Sheets, donde no hay una persona detrás. Un
/// filtro de "asignadas por" que simplemente las dejara por fuera daría
/// totales que no cuadran con la lista — el mismo error del contador de
/// "Publicados".
///
/// Así que no hay tarea sin autor: hay tres clases de autor, y las tres se
/// pueden contar y filtrar.
library;

import '../../models/task_model.dart';

/// Clave con la que se agrupa y filtra por autor.
///
/// Para una persona es su id de usuario, para que sirva de llave contra el
/// catálogo. Los otros dos casos usan claves que no pueden chocar con un id
/// de Firestore porque llevan dos puntos.
abstract final class AutorTarea {
  /// La creó el puente de Google Sheets, sin una persona detrás.
  static const hoja = 'via:hoja';

  /// Nació antes de que CheCu guardara quién asignaba.
  static const sinRegistrar = 'via:sin-registrar';

  /// Cómo se llama cada caso especial en pantalla.
  static const nombres = {
    hoja: 'Hoja de cálculo',
    sinRegistrar: 'Sin registrar',
  };
}

/// La clave de autor de [t]: su id de usuario, o uno de los dos casos
/// especiales de [AutorTarea].
String claveAutor(TaskModel t) {
  final id = t.createdBy;
  if (id != null && id.isNotEmpty) return id;
  return t.createdVia == 'hoja' ? AutorTarea.hoja : AutorTarea.sinRegistrar;
}

/// Cómo se lee esa clave. [nombreDeUsuario] resuelve los ids de personas
/// contra el catálogo; devuelve null cuando el usuario ya no existe, y ahí
/// se dice eso mismo en vez de dejar un id crudo en pantalla.
String nombreAutor(String clave, String? Function(String id) nombreDeUsuario) {
  final especial = AutorTarea.nombres[clave];
  if (especial != null) return especial;
  return nombreDeUsuario(clave) ?? 'Usuario eliminado';
}

/// Cuántas tareas asignó cada quien, de mayor a menor.
///
/// Devuelve claves de autor, no nombres: quien llame decide cómo mostrarlas
/// y con qué catálogo resolverlas.
List<MapEntry<String, int>> tareasPorAutor(Iterable<TaskModel> tareas) {
  final cuenta = <String, int>{};
  for (final t in tareas) {
    final k = claveAutor(t);
    cuenta[k] = (cuenta[k] ?? 0) + 1;
  }
  final lista = cuenta.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return lista;
}
