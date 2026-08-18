import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/constants/app_constants.dart';
import 'package:taskflow_executive/core/utils/report_metrics.dart';
import 'package:taskflow_executive/models/app_user.dart';
import 'package:taskflow_executive/models/task_model.dart';

/// Tests for the metrics that need the catalog — the big Dashboard numbers.
///
/// These were untestable until `TaskCatalog` was extracted: they took the
/// whole `CatalogProvider`, which opens Firestore streams in its constructor.
/// The fake below is the entire dependency now, which is the point.
class _CatalogoFalso implements TaskCatalog {
  _CatalogoFalso({this.usuarios = const []});

  final List<AppUser> usuarios;

  @override
  String? get completedStatusId => 'completada';
  @override
  String? get pendingStatusId => 'pendiente';
  @override
  String? get rescheduledStatusId => 'reprogramada';

  @override
  String statusName(String? id) => id ?? '-';

  @override
  AppUser? userById(String? id) {
    for (final u in usuarios) {
      if (u.id == id) return u;
    }
    return null;
  }
}

/// Un catálogo de una empresa que todavía no creó sus estados: todos null.
class _CatalogoVacio extends _CatalogoFalso {
  @override
  String? get completedStatusId => null;
  @override
  String? get pendingStatusId => null;
  @override
  String? get rescheduledStatusId => null;
}

void main() {
  TaskModel tarea({
    String id = 't',
    String estado = 'pendiente',
    String? grupo,
    String usuario = 'u1',
  }) =>
      TaskModel(
        id: id,
        hour: '10:00',
        assignedUserId: usuario,
        clientName: 'C',
        clientPhone: '300',
        statusId: estado,
        date: '2026-08-15',
        groupId: grupo,
      );

  group('computeTaskKpis', () {
    test('cuenta cada estado por separado', () {
      final k = computeTaskKpis([
        tarea(estado: 'completada'),
        tarea(estado: 'completada'),
        tarea(estado: 'pendiente'),
        tarea(estado: 'reprogramada'),
      ], _CatalogoFalso());

      expect(k.total, 4);
      expect(k.completed, 2);
      expect(k.pending, 1);
      expect(k.rescheduled, 1);
    });

    test('el cumplimiento se redondea', () {
      // 1 de 3 = 33.33% -> 33
      final k = computeTaskKpis([
        tarea(estado: 'completada'),
        tarea(estado: 'pendiente'),
        tarea(estado: 'pendiente'),
      ], _CatalogoFalso());
      expect(k.compliancePercent, 33);
    });

    test('sin tareas el cumplimiento es 0, no una división por cero', () {
      expect(computeTaskKpis([], _CatalogoFalso()).compliancePercent, 0);
    });

    test('una empresa sin estados creados no cuenta nada como completado', () {
      // Si esto contara mal, el Dashboard mostraría 100% de cumplimiento
      // a una empresa recién creada.
      final k = computeTaskKpis([tarea(estado: 'completada')], _CatalogoVacio());
      expect(k.total, 1);
      expect(k.completed, 0);
      expect(k.compliancePercent, 0);
    });
  });

  group('computeGroupCompliance', () {
    test('separa el conteo por equipo', () {
      final r = computeGroupCompliance([
        tarea(grupo: 'A', estado: 'completada'),
        tarea(grupo: 'A', estado: 'pendiente'),
        tarea(grupo: 'B', estado: 'completada'),
      ], _CatalogoFalso());

      final a = r.firstWhere((g) => g.groupId == 'A');
      final b = r.firstWhere((g) => g.groupId == 'B');
      expect(a.assigned, 2);
      expect(a.completed, 1);
      expect(a.percent, 50);
      expect(b.percent, 100);
    });

    test('un equipo sin completadas da 0, no se omite del informe', () {
      final r = computeGroupCompliance([tarea(grupo: 'A')], _CatalogoFalso());
      expect(r.single.percent, 0);
      expect(r.single.assigned, 1);
    });

    test('bestGroupCompliance devuelve el de mayor porcentaje', () {
      final r = computeGroupCompliance([
        tarea(grupo: 'A', estado: 'completada'),
        tarea(grupo: 'B', estado: 'pendiente'),
      ], _CatalogoFalso());
      expect(bestGroupCompliance(r)?.groupId, 'A');
    });

    test('sin equipos devuelve null', () {
      expect(bestGroupCompliance([]), isNull);
    });
  });

  group('computeStatusDistribution', () {
    test('agrupa por nombre de estado', () {
      final d = computeStatusDistribution([
        tarea(estado: 'completada'),
        tarea(estado: 'completada'),
        tarea(estado: 'pendiente'),
      ], _CatalogoFalso());
      expect(d, {'completada': 2, 'pendiente': 1});
    });
  });

  group('topUserByCompleted', () {
    AppUser persona(String id) => AppUser(
          id: id, email: '$id@x.com', name: id, role: AppRoles.trabajadorNormal,
        );

    test('devuelve quien más completó', () {
      final cat = _CatalogoFalso(usuarios: [persona('ana'), persona('luis')]);
      final r = topUserByCompleted([
        tarea(usuario: 'ana', estado: 'completada'),
        tarea(usuario: 'ana', estado: 'completada'),
        tarea(usuario: 'luis', estado: 'completada'),
      ], cat);
      expect(r?.name, 'ana');
    });

    test('ignora las no completadas al decidir', () {
      final cat = _CatalogoFalso(usuarios: [persona('ana'), persona('luis')]);
      final r = topUserByCompleted([
        tarea(usuario: 'ana', estado: 'pendiente'),
        tarea(usuario: 'ana', estado: 'pendiente'),
        tarea(usuario: 'luis', estado: 'completada'),
      ], cat);
      expect(r?.name, 'luis');
    });

    test('sin tareas completadas devuelve null', () {
      final cat = _CatalogoFalso(usuarios: [persona('ana')]);
      expect(topUserByCompleted([tarea(usuario: 'ana')], cat), isNull);
    });
  });
}
