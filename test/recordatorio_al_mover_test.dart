import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/recordatorio_al_mover.dart';

void main() {
  // El caso que reportó Michel: instalación hoy a las 4:00 p. m. con
  // recordatorio 15 minutos antes, reprogramada para dentro de cuatro días.
  final hoy4pm = DateTime(2026, 11, 13, 16, 0);
  final quinceAntes = DateTime(2026, 11, 13, 15, 45);
  final ahora = DateTime(2026, 11, 13, 10, 0);

  group('el recordatorio sigue a la tarea', () {
    test('cuatro días después, suena 15 minutos antes de ESE día', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: hoy4pm,
        momentoNuevo: DateTime(2026, 11, 17, 16, 0),
        ahora: ahora,
      );
      expect(r.instante, DateTime(2026, 11, 17, 15, 45));
      expect(r.seQuito, isFalse);
    });

    test('si además cambia la hora, los 15 minutos se respetan', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: hoy4pm,
        momentoNuevo: DateTime(2026, 11, 17, 9, 30),
        ahora: ahora,
      );
      expect(r.instante, DateTime(2026, 11, 17, 9, 15));
    });

    test('una hora antes se mantiene en una hora antes', () {
      final r = moverRecordatorio(
        recordatorioActual: DateTime(2026, 11, 13, 15, 0),
        momentoAnterior: hoy4pm,
        momentoNuevo: DateTime(2026, 11, 20, 8, 0),
        ahora: ahora,
      );
      expect(r.instante, DateTime(2026, 11, 20, 7, 0));
    });

    test('un recordatorio personalizado de dos días antes también se mueve', () {
      final r = moverRecordatorio(
        recordatorioActual: DateTime(2026, 11, 11, 9, 0),
        momentoAnterior: hoy4pm,
        momentoNuevo: DateTime(2026, 11, 23, 16, 0),
        ahora: ahora,
      );
      expect(r.instante, DateTime(2026, 11, 21, 9, 0));
    });

    test('mover la tarea hacia atrás también lo mueve hacia atrás', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: hoy4pm,
        momentoNuevo: DateTime(2026, 11, 13, 18, 0),
        ahora: ahora,
      );
      expect(r.instante, DateTime(2026, 11, 13, 17, 45));
    });
  });

  group('cuando ya no alcanza', () {
    test('si el nuevo momento ya pasó, se quita y se avisa', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: hoy4pm,
        // La tarea se pasa para dentro de cinco minutos: quince minutos
        // antes de eso ya pasó hace rato.
        momentoNuevo: DateTime(2026, 11, 13, 10, 5),
        ahora: ahora,
      );
      expect(r.instante, isNull);
      expect(r.seQuito, isTrue);
    });

    test('justo en este instante tampoco alcanza', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: hoy4pm,
        momentoNuevo: DateTime(2026, 11, 13, 10, 15),
        ahora: ahora,
      );
      expect(r.seQuito, isTrue);
    });

    test('un minuto después sí alcanza', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: hoy4pm,
        momentoNuevo: DateTime(2026, 11, 13, 10, 16),
        ahora: ahora,
      );
      expect(r.instante, DateTime(2026, 11, 13, 10, 1));
      expect(r.seQuito, isFalse);
    });
  });

  group('cuando no hay nada que calcular', () {
    test('sin recordatorio no se inventa ninguno', () {
      final r = moverRecordatorio(
        recordatorioActual: null,
        momentoAnterior: hoy4pm,
        momentoNuevo: DateTime(2026, 11, 17, 16, 0),
        ahora: ahora,
      );
      expect(r.instante, isNull);
      expect(r.seQuito, isFalse);
    });

    test('sin hora nueva se deja como estaba', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: hoy4pm,
        momentoNuevo: null,
        ahora: ahora,
      );
      expect(r.instante, quinceAntes);
      expect(r.seQuito, isFalse);
    });

    test('sin hora anterior se deja como estaba', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: null,
        momentoNuevo: DateTime(2026, 11, 17, 16, 0),
        ahora: ahora,
      );
      expect(r.instante, quinceAntes);
    });

    test('si la tarea no se movió, el recordatorio no se mueve', () {
      final r = moverRecordatorio(
        recordatorioActual: quinceAntes,
        momentoAnterior: hoy4pm,
        momentoNuevo: hoy4pm,
        ahora: ahora,
      );
      expect(r.instante, quinceAntes);
      expect(r.seQuito, isFalse);
    });
  });
}
