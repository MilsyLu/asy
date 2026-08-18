import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/constants/app_constants.dart';
import 'package:taskflow_executive/core/utils/task_visibility.dart';
import 'package:taskflow_executive/models/app_user.dart';
import 'package:taskflow_executive/models/task_model.dart';

/// Tests for the single source of truth on client-side task visibility.
///
/// This is the highest-stakes pure function in the app: it decides which
/// tasks a person sees, and `firestore.rules` (`canAccessTask()`) is meant to
/// mirror it exactly. A mistake here does not crash anything — it quietly
/// shows one team's work to another, which is the kind of bug nobody reports
/// because it looks like the app working.
///
/// The multi-team migration rewrote this logic (a user went from belonging to
/// one team to many), so the multi-team cases below are the ones most worth
/// pinning down.
void main() {
  AppUser usuario({
    String role = AppRoles.trabajadorNormal,
    List<String> groupIds = const [],
    List<String> managedGroupIds = const [],
  }) =>
      AppUser(
        id: 'u1',
        email: 'u@x.com',
        name: 'Usuario',
        role: role,
        groupIds: groupIds,
        managedGroupIds: managedGroupIds,
      );

  TaskModel tarea({String? groupId, bool visibleToAllGroups = false}) => TaskModel(
        id: 't1',
        hour: '10:00',
        assignedUserId: 'otro',
        clientName: 'Cliente',
        clientPhone: '300',
        statusId: 's1',
        date: '2026-08-15',
        groupId: groupId,
        visibleToAllGroups: visibleToAllGroups,
      );

  bool ve(AppUser u, TaskModel t) => isTaskVisibleToUser(task: t, user: u);

  group('trabajador normal', () {
    test('ve las tareas de su equipo', () {
      expect(ve(usuario(groupIds: ['A']), tarea(groupId: 'A')), isTrue);
    });

    test('NO ve las de otro equipo', () {
      expect(ve(usuario(groupIds: ['A']), tarea(groupId: 'B')), isFalse);
    });

    test('sin equipo no ve nada de ningún equipo', () {
      expect(ve(usuario(), tarea(groupId: 'A')), isFalse);
    });
  });

  group('multi-equipo (lo que cambió en la migración)', () {
    test('ve las tareas de TODOS sus equipos', () {
      final u = usuario(groupIds: ['A', 'B']);
      expect(ve(u, tarea(groupId: 'A')), isTrue);
      expect(ve(u, tarea(groupId: 'B')), isTrue);
    });

    test('pertenecer a dos equipos no da acceso a un tercero', () {
      expect(ve(usuario(groupIds: ['A', 'B']), tarea(groupId: 'C')), isFalse);
    });
  });

  group('tareas compartidas', () {
    test('visibleToAllGroups la muestra a cualquiera con equipo propio', () {
      expect(ve(usuario(groupIds: ['Z']), tarea(groupId: 'A', visibleToAllGroups: true)), isTrue);
    });
  });

  group('administradores', () {
    test('super_admin ve todo, incluso tareas sin equipo', () {
      final u = usuario(role: AppRoles.superAdmin);
      expect(ve(u, tarea(groupId: 'A')), isTrue);
      expect(ve(u, tarea()), isTrue);
    });

    test('admin_equipo ve lo de los equipos que gestiona', () {
      expect(ve(usuario(role: AppRoles.adminEquipo, managedGroupIds: ['A']), tarea(groupId: 'A')), isTrue);
    });

    test('admin_equipo NO ve lo de un equipo que no gestiona', () {
      expect(ve(usuario(role: AppRoles.adminEquipo, managedGroupIds: ['A']), tarea(groupId: 'B')), isFalse);
    });
  });

  group('tareas antiguas sin equipo', () {
    test('quedan ocultas para un trabajador hasta que se les asigne uno', () {
      // Compatibilidad: existen tareas anteriores a los equipos. Deben
      // esconderse, no filtrarse a todo el mundo por no tener groupId.
      expect(ve(usuario(groupIds: ['A']), tarea()), isFalse);
    });

    test('ni siquiera visibleToAllGroups las expone si no tienen equipo', () {
      expect(ve(usuario(groupIds: ['A']), tarea(visibleToAllGroups: true)), isFalse);
    });
  });
}
