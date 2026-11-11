import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/autor_tarea.dart';
import 'package:taskflow_executive/models/task_model.dart';

/// Pruebas de quién figura como autor de una tarea.
///
/// Lo que importa aquí no es el caso bonito —la tarea que alguien creó desde
/// la app— sino los dos feos: la que entró por la hoja de cálculo y la que
/// nació antes de que CheCu guardara el dato. Si esos dos no se pudieran
/// contar, cualquier total de "asignadas por" sería menor que la lista que
/// lo acompaña, y es justo el tipo de número que lleva a decidir mal.
void main() {
  TaskModel tarea({String? createdBy, String? createdVia}) => TaskModel(
    id: 't1',
    hour: '09:00',
    assignedUserId: 'u-natalia',
    clientName: 'Sabrosia',
    clientPhone: '',
    statusId: 's1',
    date: '2026-11-03',
    createdBy: createdBy,
    createdVia: createdVia,
  );

  test('la asignó una persona', () {
    expect(claveAutor(tarea(createdBy: 'u-elena')), 'u-elena');
  });

  test('vino de la hoja de cálculo', () {
    expect(claveAutor(tarea(createdVia: 'hoja')), AutorTarea.hoja);
  });

  test('nació antes de que se guardara el autor', () {
    expect(claveAutor(tarea()), AutorTarea.sinRegistrar);
  });

  test('un createdBy vacío cuenta como sin registrar, no como persona', () {
    // Firestore devuelve cadena vacía donde otro código esperaba null; sin
    // esto, el filtro mostraría una persona llamada "".
    expect(claveAutor(tarea(createdBy: '')), AutorTarea.sinRegistrar);
  });

  test('la persona manda sobre el origen', () {
    // Si alguna vez una tarea trae las dos cosas, quien la asignó es la
    // persona: la hoja es el caso en que no hay nadie.
    expect(
      claveAutor(tarea(createdBy: 'u-elena', createdVia: 'hoja')),
      'u-elena',
    );
  });

  test('los casos especiales tienen nombre propio en pantalla', () {
    expect(nombreAutor(AutorTarea.hoja, (_) => null), 'Hoja de cálculo');
    expect(nombreAutor(AutorTarea.sinRegistrar, (_) => null), 'Sin registrar');
  });

  test('una persona que ya no existe no deja un id crudo a la vista', () {
    expect(nombreAutor('u-borrado', (_) => null), 'Usuario eliminado');
  });

  test('resuelve el nombre de la persona contra el catálogo', () {
    expect(nombreAutor('u-elena', (id) => 'Elena'), 'Elena');
  });

  test('el conteo por autor suma todas las tareas, no sólo las que tienen '
      'persona', () {
    final tareas = [
      tarea(createdBy: 'u-elena'),
      tarea(createdBy: 'u-elena'),
      tarea(createdVia: 'hoja'),
      tarea(),
    ];
    final porAutor = tareasPorAutor(tareas);
    expect(porAutor.first.key, 'u-elena');
    expect(porAutor.first.value, 2);
    expect(
      porAutor.fold<int>(0, (a, e) => a + e.value),
      tareas.length,
      reason: 'el total por autor tiene que cuadrar con el total de tareas',
    );
  });
}
