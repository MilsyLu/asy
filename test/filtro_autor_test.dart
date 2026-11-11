import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/autor_tarea.dart';
import 'package:taskflow_executive/models/task_model.dart';
import 'package:taskflow_executive/providers/filtro_autor_provider.dart';
import 'package:taskflow_executive/widgets/filtro_autor_chip.dart';

/// Pruebas del filtro de "asignadas por" que comparten Calendario y Agenda.
///
/// Las cuatro vistas llaman a la misma función, así que lo que se fije aquí
/// vale para las cuatro. Si cada pantalla filtrara por su cuenta, esto
/// probaría una de ellas y las otras tres podrían estar equivocadas.
void main() {
  TaskModel tarea({
    required String id,
    String? asignadaPor,
    String? via,
    String encargado = 'u-natalia',
  }) => TaskModel(
    id: id,
    hour: '09:00',
    assignedUserId: encargado,
    clientName: 'Sabrosia',
    clientPhone: '',
    statusId: 's1',
    date: '2026-11-03',
    createdBy: asignadaPor,
    createdVia: via,
  );

  final tareas = [
    tarea(id: 'elena1', asignadaPor: 'u-elena'),
    tarea(id: 'elena2', asignadaPor: 'u-elena'),
    tarea(id: 'michel', asignadaPor: 'u-michel'),
    tarea(id: 'hoja', via: 'hoja'),
    tarea(id: 'vieja'),
  ];

  group('aplicar el filtro', () {
    test('sin filtro devuelve la misma lista, sin copiarla', () {
      expect(aplicarFiltroAutor(tareas, null), same(tareas));
    });

    test('deja solo lo que asignó esa persona', () {
      expect(aplicarFiltroAutor(tareas, 'u-elena').map((t) => t.id), [
        'elena1',
        'elena2',
      ]);
    });

    test('las de la hoja y las viejas también se pueden aislar', () {
      expect(aplicarFiltroAutor(tareas, AutorTarea.hoja).map((t) => t.id), [
        'hoja',
      ]);
      expect(
        aplicarFiltroAutor(tareas, AutorTarea.sinRegistrar).map((t) => t.id),
        ['vieja'],
      );
    });

    test('filtrar por alguien que no asignó nada da vacío, no todo', () {
      // El error clásico: tratar "no coincide ninguna" como "no filtres".
      // En una agenda, mostrar todo cuando el filtro no encuentra nada se
      // lee como que esa persona asignó el día entero.
      expect(aplicarFiltroAutor(tareas, 'u-nadie'), isEmpty);
    });

    test('filtra por quien asignó, no por quien la tiene', () {
      final t = [
        tarea(id: 'x', asignadaPor: 'u-elena', encargado: 'u-natalia'),
      ];
      expect(aplicarFiltroAutor(t, 'u-elena').length, 1);
      expect(aplicarFiltroAutor(t, 'u-natalia'), isEmpty);
    });
  });

  group('el estado compartido', () {
    test('arranca mostrando todo', () {
      final f = FiltroAutorProvider();
      expect(f.autor, isNull);
      expect(f.activo, isFalse);
    });

    test('avisa al cambiar y al limpiar', () {
      final f = FiltroAutorProvider();
      var avisos = 0;
      f.addListener(() => avisos++);

      f.cambiar('u-elena');
      expect(f.activo, isTrue);
      expect(avisos, 1);

      f.limpiar();
      expect(f.autor, isNull);
      expect(avisos, 2);
    });

    test('elegir dos veces lo mismo no redibuja las cuatro vistas', () {
      final f = FiltroAutorProvider();
      var avisos = 0;
      f.addListener(() => avisos++);
      f.cambiar('u-elena');
      f.cambiar('u-elena');
      expect(avisos, 1);
    });
  });
}
