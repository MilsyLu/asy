import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/reschedule_summary.dart';
import 'package:taskflow_executive/models/task_model.dart';

/// Pruebas de la frase que explica una reprogramación.
///
/// Nacen de una pregunta concreta de Michel mirando el calendario: dos tareas
/// marcadas "Reprogramada" el 7 de octubre, y ninguna forma de saber de qué
/// fecha venían ni por qué seguían ahí.
void main() {
  RescheduleEntry desde(String fecha, String hora) =>
      RescheduleEntry(fromDate: fecha, fromHour: hora);

  test('una tarea que nunca se movió no dice nada', () {
    expect(
      rescheduleSummary(
        history: const [],
        rescheduledCount: 0,
        currentDate: '2026-10-07',
      ),
      isNull,
    );
  });

  test('dice de qué fecha y hora venía', () {
    expect(
      rescheduleSummary(
        history: [desde('2026-10-05', '10:00')],
        rescheduledCount: 1,
        currentDate: '2026-10-07',
      ),
      'Antes: 5 oct 10:00',
    );
  });

  test('distingue cuando sólo cambió la hora', () {
    // La confusión que reportó Michel: reprogramar sólo la hora también marca
    // la tarea como "Reprogramada", así que una tarea que nunca cambió de día
    // parecía haberse ido a otro.
    expect(
      rescheduleSummary(
        history: [desde('2026-10-07', '10:00')],
        rescheduledCount: 1,
        currentDate: '2026-10-07',
      ),
      'Antes a las 10:00, el mismo día',
    );
  });

  test('con varias reprogramaciones muestra la última y cuántas van', () {
    expect(
      rescheduleSummary(
        history: [desde('2026-10-01', '08:00'), desde('2026-10-05', '10:00')],
        rescheduledCount: 2,
        currentDate: '2026-10-07',
      ),
      'Antes: 5 oct 10:00 · 2 veces',
    );
  });

  test('una tarea vieja dice que no hay registro, en vez de callarlo', () {
    // Perro Loco y SAMARIO: se movieron antes de que esto existiera, así que
    // su fecha anterior ya estaba sobrescrita. Inventarla no es opción y
    // ocultar que se movieron, tampoco.
    expect(
      rescheduleSummary(
        history: const [],
        rescheduledCount: 2,
        currentDate: '2026-10-07',
      ),
      'Sin registro de la fecha anterior · 2 veces',
    );
  });

  test('un historial más corto que el contador no pierde las veces', () {
    // Pasa en una tarea movida antes y después del cambio: el contador sabe
    // que van tres, el historial sólo recuerda la última.
    expect(
      rescheduleSummary(
        history: [desde('2026-10-05', '10:00')],
        rescheduledCount: 3,
        currentDate: '2026-10-07',
      ),
      'Antes: 5 oct 10:00 · 3 veces',
    );
  });

  group('rescheduleChain', () {
    test('muestra el recorrido entero, terminando donde está hoy', () {
      expect(
        rescheduleChain(
          history: [desde('2026-10-01', '08:00'), desde('2026-10-05', '10:00')],
          rescheduledCount: 2,
          currentDate: '2026-10-07',
          currentHour: '15:30',
        ),
        '1 oct 08:00  →  5 oct 10:00  →  7 oct 15:30',
      );
    });

    test('una tarea sin mover no tiene recorrido', () {
      expect(
        rescheduleChain(
          history: const [],
          rescheduledCount: 0,
          currentDate: '2026-10-07',
          currentHour: '15:30',
        ),
        isNull,
      );
    });

    test('una tarea vieja dice cuántas veces y que no quedó registro', () {
      final t = rescheduleChain(
        history: const [],
        rescheduledCount: 2,
        currentDate: '2026-10-07',
        currentHour: '15:30',
      );
      expect(t, contains('2 veces'));
      expect(t, contains('no quedaron registradas'));
    });
  });

  group('shortDateKey', () {
    test('convierte la clave a algo legible', () {
      expect(shortDateKey('2026-10-05'), '5 oct');
      expect(shortDateKey('2026-01-31'), '31 ene');
    });

    test('una fecha malformada se muestra cruda en vez de reventar', () {
      expect(shortDateKey('sin fecha'), 'sin fecha');
      expect(shortDateKey('2026-13-05'), '2026-13-05');
    });
  });
}
