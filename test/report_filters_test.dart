import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/report_filters.dart';
import 'package:taskflow_executive/models/task_model.dart';

/// Tests for the Reportes filters.
///
/// These decide which rows a person sees *and* which rows land in the export,
/// so a filter that drops one row too many produces a spreadsheet that looks
/// complete and is not. There is nothing on screen that would reveal it.
void main() {
  TaskModel tarea({
    String id = 't',
    String cliente = 'Cliente',
    String telefono = '3005551234',
    String usuario = 'u1',
    String? grupo = 'g1',
    String estado = 'pendiente',
    String? tipo = 'instalacion',
  }) => TaskModel(
    id: id,
    hour: '10:00',
    assignedUserId: usuario,
    clientName: cliente,
    clientPhone: telefono,
    statusId: estado,
    taskTypeId: tipo,
    groupId: grupo,
    date: '2026-08-15',
  );

  group('sin filtros', () {
    test('no toca la lista', () {
      const f = ReportFilters();
      expect(f.isEmpty, isTrue);
      final tareas = [tarea(id: 'a'), tarea(id: 'b')];
      expect(f.apply(tareas), same(tareas), reason: 'ni siquiera la copia');
    });

    test('espacios en blanco no cuentan como búsqueda', () {
      expect(const ReportFilters(search: '   ').isEmpty, isTrue);
    });
  });

  group('búsqueda por cliente', () {
    test('encuentra sin importar mayúsculas', () {
      final r = const ReportFilters(search: 'KAYROS').apply([
        tarea(id: 'a', cliente: 'Kayros Burger'),
        tarea(id: 'b', cliente: 'Otro'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });

    test('encuentra sin escribir la tilde', () {
      // Nadie escribe "Café" con tilde cuando está buscando.
      final r = const ReportFilters(search: 'cafe').apply([
        tarea(id: 'a', cliente: 'Primaveral Café'),
        tarea(id: 'b', cliente: 'Otro'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });

    test('encuentra la ñ escrita sin virgulilla', () {
      final r = const ReportFilters(search: 'panaderia').apply([
        tarea(id: 'a', cliente: 'Panadería los andes'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });

    test('busca en cualquier parte del nombre, no solo al principio', () {
      final r = const ReportFilters(search: 'burger').apply([
        tarea(id: 'a', cliente: 'KAYROS BURGER'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });
  });

  group('búsqueda por teléfono', () {
    test('ignora espacios y guiones de ambos lados', () {
      final r = const ReportFilters(search: '304 550').apply([
        tarea(id: 'a', telefono: '304-550-2708'),
        tarea(id: 'b', telefono: '3115551234'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });

    test('un texto sin dígitos no se compara contra el teléfono', () {
      final r = const ReportFilters(search: 'zzz').apply([
        tarea(id: 'a', telefono: '3005551234'),
      ]);
      expect(r, isEmpty);
    });
  });

  group('filtros por lista', () {
    test('equipo', () {
      final r = const ReportFilters(groupId: 'g1').apply([
        tarea(id: 'a', grupo: 'g1'),
        tarea(id: 'b', grupo: 'g2'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });

    test('usuario', () {
      final r = const ReportFilters(userId: 'u2').apply([
        tarea(id: 'a', usuario: 'u1'),
        tarea(id: 'b', usuario: 'u2'),
      ]);
      expect(r.map((t) => t.id), ['b']);
    });

    test('estado', () {
      final r = const ReportFilters(statusId: 'completada').apply([
        tarea(id: 'a', estado: 'completada'),
        tarea(id: 'b', estado: 'pendiente'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });

    test('tipo de tarea', () {
      final r = const ReportFilters(taskTypeId: 'impresoras').apply([
        tarea(id: 'a', tipo: 'impresoras'),
        tarea(id: 'b', tipo: 'instalacion'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });

    test('una tarea sin equipo no entra al filtrar por equipo', () {
      final r = const ReportFilters(groupId: 'g1').apply([
        tarea(id: 'a', grupo: null),
      ]);
      expect(r, isEmpty);
    });

    test('"Sin equipo" alcanza justo las que no tienen equipo', () {
      // Sin esta opción esas tareas no las selecciona ningún filtro: quedan
      // fuera de toda vista filtrada y de todo export, sin aviso.
      final r = const ReportFilters(groupId: kSinAsignar).apply([
        tarea(id: 'a', grupo: null),
        tarea(id: 'b', grupo: 'g1'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });

    test('"Sin tipo" hace lo mismo con el tipo de tarea', () {
      final r = const ReportFilters(taskTypeId: kSinAsignar).apply([
        tarea(id: 'a', tipo: null),
        tarea(id: 'b', tipo: 'instalacion'),
      ]);
      expect(r.map((t) => t.id), ['a']);
    });
  });

  test('los filtros se acumulan, no se reemplazan', () {
    // El caso que más importa: cada condición recorta, y una fila tiene que
    // cumplirlas todas. Si se aplicaran por separado el export saldría de más.
    const f = ReportFilters(
      search: 'burger',
      groupId: 'g1',
      statusId: 'completada',
    );
    final r = f.apply([
      tarea(id: 'ok', cliente: 'Allitas Burger', grupo: 'g1', estado: 'completada'),
      tarea(id: 'otroEquipo', cliente: 'Allitas Burger', grupo: 'g2', estado: 'completada'),
      tarea(id: 'otroEstado', cliente: 'Allitas Burger', grupo: 'g1', estado: 'pendiente'),
      tarea(id: 'otroCliente', cliente: 'Pizza', grupo: 'g1', estado: 'completada'),
    ]);
    expect(r.map((t) => t.id), ['ok']);
  });

  group('copyWith', () {
    test('limpia un filtro sin tocar los demás', () {
      const f = ReportFilters(groupId: 'g1', userId: 'u1', search: 'x');
      final sinEquipo = f.copyWith(clearGroup: true);
      expect(sinEquipo.groupId, isNull);
      expect(sinEquipo.userId, 'u1');
      expect(sinEquipo.search, 'x');
    });

    test('cambiar uno no borra el resto', () {
      const f = ReportFilters(groupId: 'g1', search: 'x');
      final conUsuario = f.copyWith(userId: 'u9');
      expect(conUsuario.groupId, 'g1');
      expect(conUsuario.search, 'x');
      expect(conUsuario.userId, 'u9');
    });
  });
}
