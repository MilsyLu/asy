import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/constants/app_constants.dart';
import 'package:taskflow_executive/core/utils/date_utils.dart';
import 'package:taskflow_executive/core/utils/report_metrics.dart';
import 'package:taskflow_executive/models/app_user.dart';
import 'package:taskflow_executive/models/task_model.dart';

/// Tests for the Dashboard/Reportes calculations that need no catalog.
///
/// These feed numbers a person makes decisions with — who the busiest client
/// is, which tasks are about to come due, who has the best streak. A mistake
/// here never throws: it just prints a wrong number, confidently, forever.
/// That makes them worth pinning down more than most code that *can* crash.
/// `mostAttendedClient` needs the catalog only to know which status means
/// "cancelada" — everything else it does is pure counting.
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

void main() {
  final catalogo = _Catalogo();

  TaskModel tarea({
    String id = 't',
    String cliente = 'Cliente',
    String telefono = '300',
    String fecha = '2026-08-15',
    String hora = '10:00',
    String estado = 'pendiente',
    String? clienteId,
  }) =>
      TaskModel(
        id: id,
        hour: hora,
        assignedUserId: 'u',
        clientName: cliente,
        clientPhone: telefono,
        clientId: clienteId,
        statusId: estado,
        date: fecha,
      );

  group('mostAttendedClient', () {
    test('devuelve el cliente con más tareas', () {
      final r = mostAttendedClient([
        tarea(cliente: 'Agua Viva'),
        tarea(cliente: 'Mittsu'),
        tarea(cliente: 'Agua Viva'),
      ], catalogo);
      expect(r?.name, 'Agua Viva');
      expect(r?.count, 2);
    });

    test('distingue dos clientes con el mismo nombre y distinto teléfono', () {
      // Agrupa por nombre|teléfono, no solo por nombre: dos negocios
      // homónimos no deben sumarse en el mismo total.
      final r = mostAttendedClient([
        tarea(cliente: 'Copias', telefono: '111'),
        tarea(cliente: 'Copias', telefono: '222'),
        tarea(cliente: 'Copias', telefono: '222'),
      ], catalogo);
      expect(r?.phone, '222');
      expect(r?.count, 2);
    });

    test('sin tareas devuelve null en vez de romper', () {
      expect(mostAttendedClient([], catalogo), isNull);
    });

    test('agrupa por clientId aunque el nombre haya cambiado', () {
      // El caso que rompía el conteo: al mismo cliente le corrigen el nombre
      // o le cambian el teléfono, y pasaba a contar como dos clientes
      // distintos, con lo que ninguna de las dos mitades ganaba.
      final r = mostAttendedClient([
        tarea(cliente: 'Comedere', telefono: '300', clienteId: 'c1'),
        tarea(cliente: 'Comedere SAS', telefono: '311', clienteId: 'c1'),
        tarea(cliente: 'Otro', telefono: '999', clienteId: 'c2'),
      ], catalogo);
      expect(r?.count, 2);
    });

    test('no cuenta las canceladas', () {
      // Una visita cancelada no es atención que el cliente haya recibido.
      final r = mostAttendedClient([
        tarea(cliente: 'Agua Viva', clienteId: 'c1'),
        tarea(cliente: 'Agua Viva', clienteId: 'c1', estado: 'cancelada'),
        tarea(cliente: 'Mittsu', clienteId: 'c2'),
        tarea(cliente: 'Mittsu', clienteId: 'c2'),
      ], catalogo);
      expect(r?.name, 'Mittsu');
      expect(r?.count, 2);
    });

    test('devuelve null si todas las tareas están canceladas', () {
      expect(
        mostAttendedClient([
          tarea(cliente: 'Agua Viva', estado: 'cancelada'),
        ], catalogo),
        isNull,
      );
    });
  });

  group('computeDailyTrend', () {
    test('incluye los días sin tareas como cero', () {
      // Si los días vacíos se omitieran, el gráfico mentiría: uniría dos
      // fechas lejanas como si fueran consecutivas.
      final r = computeDailyTrend(
        [tarea(fecha: '2026-08-15'), tarea(fecha: '2026-08-15')],
        DateTime(2026, 8, 14),
        DateTime(2026, 8, 16),
        AppDateUtils.formatDateKey,
      );
      expect(r.length, 3);
      expect(r.map((e) => e.value).toList(), [0, 2, 0]);
    });

    test('mantiene el orden cronológico', () {
      final r = computeDailyTrend(
        [],
        DateTime(2026, 8, 14),
        DateTime(2026, 8, 16),
        AppDateUtils.formatDateKey,
      );
      expect(r.map((e) => e.key).toList(), ['2026-08-14', '2026-08-15', '2026-08-16']);
    });
  });

  group('computeUpcomingTasks (próximas 24 horas)', () {
    final ahora = DateTime(2026, 8, 15, 12, 0);

    test('incluye lo que cae dentro de la ventana y excluye lo de después', () {
      final dentro = tarea(id: 'dentro', fecha: '2026-08-15', hora: '18:00');
      final fuera = tarea(id: 'fuera', fecha: '2026-08-16', hora: '18:00');
      final r = computeUpcomingTasks([dentro, fuera], ahora);
      expect(r.map((t) => t.id), ['dentro']);
    });

    test('excluye lo que ya pasó', () {
      final pasada = tarea(id: 'pasada', fecha: '2026-08-15', hora: '08:00');
      expect(computeUpcomingTasks([pasada], ahora), isEmpty);
    });

    test('ordena de más próxima a más lejana', () {
      final tarde = tarea(id: 'tarde', hora: '20:00');
      final pronto = tarea(id: 'pronto', hora: '13:00');
      final r = computeUpcomingTasks([tarde, pronto], ahora);
      expect(r.map((t) => t.id).toList(), ['pronto', 'tarde']);
    });
  });

  group('bestActiveStreak', () {
    AppUser conRacha(String nombre, int dias) => AppUser(
          id: nombre, email: '$nombre@x.com', name: nombre,
          role: AppRoles.trabajadorNormal, streakDays: dias,
        );

    test('devuelve la racha más alta', () {
      final r = bestActiveStreak([conRacha('a', 3), conRacha('b', 9), conRacha('c', 5)]);
      expect(r?.name, 'b');
    });

    test('sin usuarios devuelve null', () {
      expect(bestActiveStreak([]), isNull);
    });
  });
}
