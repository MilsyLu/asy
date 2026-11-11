import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/recordatorio_resumen.dart';

void main() {
  final tarea = DateTime(2026, 11, 3, 10, 0);

  test('sin recordatorio no hay línea que dibujar', () {
    expect(
      resumenRecordatorio(
        recordatorio: null,
        enviado: false,
        fechaTarea: tarea,
      ),
      isNull,
    );
  });

  test('el mismo día muestra sólo la hora', () {
    expect(
      resumenRecordatorio(
        recordatorio: DateTime(2026, 11, 3, 9, 30),
        enviado: false,
        fechaTarea: tarea,
      ),
      'Recordatorio: 09:30',
    );
  });

  test('otro día muestra también la fecha', () {
    // "09:30" a secas no dice nada si el recordatorio es la víspera.
    expect(
      resumenRecordatorio(
        recordatorio: DateTime(2026, 11, 2, 9, 30),
        enviado: false,
        fechaTarea: tarea,
      ),
      'Recordatorio: 02/11 09:30',
    );
  });

  test('cuando ya sonó, lo dice', () {
    expect(
      resumenRecordatorio(
        recordatorio: DateTime(2026, 11, 3, 9, 30),
        enviado: true,
        fechaTarea: tarea,
      ),
      'Recordatorio enviado · 09:30',
    );
  });

  test('la hora de la tarea no cambia la comparación de día', () {
    // La tarea es a las 10:00 y el recordatorio a las 23:00 del mismo día:
    // sigue siendo el mismo día, aunque sea después.
    expect(
      resumenRecordatorio(
        recordatorio: DateTime(2026, 11, 3, 23, 0),
        enviado: false,
        fechaTarea: tarea,
      ),
      'Recordatorio: 23:00',
    );
  });
}
