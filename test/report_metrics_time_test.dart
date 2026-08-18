import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/constants/app_constants.dart';
import 'package:taskflow_executive/core/utils/report_metrics.dart';
import 'package:taskflow_executive/models/app_user.dart';
import 'package:taskflow_executive/models/task_model.dart';

/// Tests for the two metrics that depend on the clock.
///
/// Time-based logic is where off-by-one errors hide best: "vencida" and "sin
/// actividad" are judgements about people's work, so a boundary that leans
/// the wrong way either nags someone whose task is not due yet or lets a
/// genuinely late one disappear. `now` is injected, so these pin the
/// boundaries exactly instead of depending on when the suite runs.
class _Catalogo implements TaskCatalog {
  @override
  String? get completedStatusId => 'completada';
  @override
  String? get pendingStatusId => 'pendiente';
  @override
  String? get rescheduledStatusId => 'reprogramada';
  @override
  String? get cancelledStatusId => 'cancelada';
  @override
  String statusName(String? id) => id ?? '-';
  @override
  AppUser? userById(String? id) => null;
}

/// Empresa recién creada: todavía no configuró sus estados.
class _CatalogoSinEstados extends _Catalogo {
  @override
  String? get completedStatusId => null;
}

void main() {
  final ahora = DateTime(2026, 8, 15, 12, 0);

  TaskModel tarea({
    String id = 't',
    String estado = 'pendiente',
    String fecha = '2026-08-15',
    String hora = '10:00',
    String usuario = 'u1',
    DateTime? completadaEn,
  }) =>
      TaskModel(
        id: id,
        hour: hora,
        assignedUserId: usuario,
        clientName: 'C',
        clientPhone: '300',
        statusId: estado,
        date: fecha,
        completedAt: completadaEn,
      );

  AppUser persona(String id) =>
      AppUser(id: id, email: '$id@x.com', name: id, role: AppRoles.trabajadorNormal);

  group('computeOverdueTasks', () {
    test('no cuenta las canceladas por muy pasadas que estén', () {
      // Una tarea cancelada no puede estar "vencida": nadie la está
      // esperando. Contarlas hacía que el tablero mandara a perseguir
      // trabajo que ya se había dado de baja.
      final r = computeOverdueTasks([
        tarea(id: 'cancelada', hora: '08:00', estado: 'cancelada'),
        tarea(id: 'pendiente', hora: '08:00'),
      ], _Catalogo(), ahora);
      expect(r.map((t) => t.id), ['pendiente']);
    });

    test('incluye lo que ya pasó y sigue sin completarse', () {
      final r = computeOverdueTasks([tarea(id: 'vieja', hora: '08:00')], _Catalogo(), ahora);
      expect(r.map((t) => t.id), ['vieja']);
    });

    test('excluye lo que ya se completó, por vieja que sea', () {
      final r = computeOverdueTasks(
        [tarea(id: 'hecha', fecha: '2026-08-01', estado: 'completada')],
        _Catalogo(),
        ahora,
      );
      expect(r, isEmpty);
    });

    test('excluye lo que todavía no llega su hora', () {
      final r = computeOverdueTasks([tarea(id: 'futura', hora: '18:00')], _Catalogo(), ahora);
      expect(r, isEmpty);
    });

    test('una tarea reprogramada al futuro deja de estar vencida', () {
      // El caso real de reprogramar: cambia la fecha, no el estado.
      final r = computeOverdueTasks(
        [tarea(id: 'movida', fecha: '2026-08-20', estado: 'reprogramada')],
        _Catalogo(),
        ahora,
      );
      expect(r, isEmpty);
    });

    test('ordena de más antigua a más reciente', () {
      final r = computeOverdueTasks([
        tarea(id: 'ayer', fecha: '2026-08-14', hora: '09:00'),
        tarea(id: 'semana', fecha: '2026-08-08', hora: '09:00'),
        tarea(id: 'hoy', fecha: '2026-08-15', hora: '09:00'),
      ], _Catalogo(), ahora);
      expect(r.map((t) => t.id).toList(), ['semana', 'ayer', 'hoy']);
    });

    test('en una empresa sin estados, lo pasado cuenta como vencido', () {
      // Nada puede marcarse como completado todavía, así que lo vencido es
      // simplemente lo que ya pasó. Se fija para que el comportamiento sea
      // intencional y no una sorpresa el día que se dé de alta una empresa.
      final r = computeOverdueTasks([tarea(hora: '08:00')], _CatalogoSinEstados(), ahora);
      expect(r, hasLength(1));
    });
  });

  group('computeInactiveUsers', () {
    test('quien completó algo hace 3 días NO aparece', () {
      final r = computeInactiveUsers(
        [tarea(usuario: 'ana', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 3)))],
        [persona('ana')],
        _Catalogo(),
        ahora,
      );
      expect(r, isEmpty);
    });

    test('quien completó algo hace 8 días SÍ aparece como inactivo', () {
      final r = computeInactiveUsers(
        [tarea(usuario: 'ana', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 8)))],
        [persona('ana')],
        _Catalogo(),
        ahora,
      );
      expect(r.map((s) => s.user.name), ['ana']);
    });

    test('justo en el límite de 7 días cuenta como activo', () {
      // El borde importa: inclinarlo mal marcaría como inactivo a alguien
      // que trabajó dentro de la ventana.
      final r = computeInactiveUsers(
        [tarea(usuario: 'ana', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 7)))],
        [persona('ana')],
        _Catalogo(),
        ahora,
      );
      expect(r, isEmpty);
    });

    test('tener tareas pendientes no salva de aparecer como inactivo', () {
      final r = computeInactiveUsers(
        [tarea(usuario: 'ana', estado: 'pendiente')],
        [persona('ana')],
        _Catalogo(),
        ahora,
      );
      expect(r.map((s) => s.user.name), ['ana']);
    });

    test('quien no tiene ninguna tarea aparece como inactivo', () {
      final r = computeInactiveUsers([], [persona('ana'), persona('luis')], _Catalogo(), ahora);
      expect(r.map((s) => s.user.name).toList(), ['ana', 'luis']);
    });

    test('una tarea vieja sin completedAt usa su hora agendada', () {
      // Compatibilidad: filas anteriores al campo completedAt. Sin esta
      // reserva, se tomarían como completadas "sin fecha" y podrían salvar
      // a alguien que lleva meses sin trabajar.
      final r = computeInactiveUsers(
        [tarea(usuario: 'ana', estado: 'completada', fecha: '2026-07-01')],
        [persona('ana')],
        _Catalogo(),
        ahora,
      );
      expect(r.map((s) => s.user.name), ['ana']);
    });

    test('distingue entre quien trabajó y quien no', () {
      final r = computeInactiveUsers(
        [tarea(usuario: 'ana', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 1)))],
        [persona('ana'), persona('luis')],
        _Catalogo(),
        ahora,
      );
      expect(r.map((s) => s.user.name).toList(), ['luis']);
    });
  });

  group('días sin completar (reemplaza la etiqueta que siempre decía 0)', () {
    test('cuenta los días desde la última completada', () {
      final r = computeInactiveUsers(
        [tarea(usuario: 'ana', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 20)))],
        [persona('ana')],
        _Catalogo(),
        ahora,
      );
      expect(r.single.daysSinceLastCompleted, 20);
    });

    test('toma la MÁS reciente cuando hay varias', () {
      final r = computeInactiveUsers(
        [
          tarea(id: 'a', usuario: 'ana', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 40))),
          tarea(id: 'b', usuario: 'ana', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 12))),
        ],
        [persona('ana')],
        _Catalogo(),
        ahora,
      );
      expect(r.single.daysSinceLastCompleted, 12);
    });

    test('quien nunca completó nada queda en null, no en 0', () {
      // La diferencia importa: 0 diría "completó hoy", que es lo contrario.
      final r = computeInactiveUsers([], [persona('ana')], _Catalogo(), ahora);
      expect(r.single.daysSinceLastCompleted, isNull);
    });

    test('ordena de peor a mejor, con los que nunca completaron primero', () {
      final r = computeInactiveUsers(
        [
          tarea(id: 'a', usuario: 'ana', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 10))),
          tarea(id: 'b', usuario: 'beto', estado: 'completada', completadaEn: ahora.subtract(const Duration(days: 45))),
        ],
        [persona('ana'), persona('beto'), persona('nunca')],
        _Catalogo(),
        ahora,
      );
      expect(r.map((s) => s.user.name).toList(), ['nunca', 'beto', 'ana']);
    });
  });
}
