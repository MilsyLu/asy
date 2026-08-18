import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/models/task_model.dart';

/// Tests for TaskModel's serialisation and derived time.
///
/// Serialisation bugs are the quiet kind: a field that stops round-tripping
/// does not throw, it just comes back empty. `updatedBy` (added today, so the
/// reschedule notification can name who moved a task) is covered here
/// precisely because losing it would look like "the notification forgot the
/// name" rather than like a bug in the model.
void main() {
  Map<String, dynamic> mapaBase() => {
        'hour': '14:30',
        'assignedUserId': 'u1',
        'clientName': 'Agua Viva',
        'clientPhone': '300',
        'statusId': 's1',
        'date': '2026-08-15',
      };

  group('fromMap', () {
    test('lee los campos básicos', () {
      final t = TaskModel.fromMap('t1', mapaBase());
      expect(t.id, 't1');
      expect(t.hour, '14:30');
      expect(t.clientName, 'Agua Viva');
      expect(t.date, '2026-08-15');
    });

    test('un documento incompleto no rompe: usa valores por defecto', () {
      // Hay tareas viejas en producción anteriores a varios campos. Si esto
      // lanzara, la lista entera dejaría de cargar por una sola fila.
      final t = TaskModel.fromMap('t1', {});
      expect(t.hour, '00:00');
      expect(t.clientName, '');
      expect(t.rescheduledCount, 0);
      expect(t.isDeleted, isFalse);
      expect(t.groupId, isNull);
      expect(t.updatedBy, isNull);
    });

    test('conserva createdBy y updatedBy', () {
      final t = TaskModel.fromMap('t1', {
        ...mapaBase(),
        'createdBy': 'quien-la-creo',
        'updatedBy': 'quien-la-reprogramo',
      });
      expect(t.createdBy, 'quien-la-creo');
      expect(t.updatedBy, 'quien-la-reprogramo');
    });
  });

  group('ida y vuelta por toMap', () {
    test('updatedBy sobrevive el viaje completo', () {
      final original = TaskModel.fromMap('t1', {
        ...mapaBase(),
        'updatedBy': 'michel',
        'groupId': 'A',
        'visibleToAllGroups': true,
        'rescheduledCount': 3,
      });
      final vuelta = TaskModel.fromMap('t1', original.toMap());

      expect(vuelta.updatedBy, 'michel');
      expect(vuelta.groupId, 'A');
      expect(vuelta.visibleToAllGroups, isTrue);
      expect(vuelta.rescheduledCount, 3);
      expect(vuelta.hour, original.hour);
      expect(vuelta.date, original.date);
    });

    test('las fechas sobreviven como Timestamp', () {
      final cuando = DateTime(2026, 8, 15, 9, 30);
      final t = TaskModel.fromMap('t1', {
        ...mapaBase(),
        'completedAt': Timestamp.fromDate(cuando),
      });
      expect(t.completedAt, cuando);
      expect(TaskModel.fromMap('t1', t.toMap()).completedAt, cuando);
    });
  });

  group('scheduledDateTime', () {
    test('combina fecha y hora', () {
      final t = TaskModel.fromMap('t1', {...mapaBase(), 'date': '2026-08-15', 'hour': '14:30'});
      expect(t.scheduledDateTime, DateTime(2026, 8, 15, 14, 30));
    });

    test('una hora malformada no rompe: cae a medianoche', () {
      final t = TaskModel.fromMap('t1', {...mapaBase(), 'hour': 'sin-hora'});
      expect(t.scheduledDateTime.hour, 0);
      expect(t.scheduledDateTime.minute, 0);
    });
  });
}
