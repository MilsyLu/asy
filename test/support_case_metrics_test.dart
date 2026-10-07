import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/constants/support_case_constants.dart';
import 'package:taskflow_executive/core/utils/support_case_metrics.dart';
import 'package:taskflow_executive/models/support_case_model.dart';

/// Pruebas de las cuentas del Resumen de Casos de Soporte.
///
/// Prueban las funciones reales que usa la pantalla, no una copia suya — la
/// lección del archivo de `client_linking_test`, donde la primera versión
/// reimplementaba la búsqueda dentro de la prueba y habría seguido en verde
/// aunque el código de producción cambiara.
void main() {
  SupportCaseModel caso({
    required DateTime reportado,
    DateTime? resuelto,
    String estado = SupportCaseStatus.nuevo,
  }) => SupportCaseModel(
    id: 'x',
    caseNumber: 1,
    empresaId: 'e1',
    clientName: 'Cliente',
    subject: 'Asunto',
    description: '',
    priority: SupportCasePriority.media,
    status: resuelto != null ? SupportCaseStatus.resuelto : estado,
    createdBy: 'u1',
    createdByName: 'Usuario',
    createdAt: reportado,
    reportedAt: reportado,
    updatedAt: reportado,
    resolvedAt: resuelto,
  );

  final lunes = DateTime(2026, 8, 31); // un lunes

  group('resolutionTime', () {
    test('un caso abierto no tiene tiempo de resolución', () {
      expect(resolutionTime(caso(reportado: lunes)), isNull);
    });

    test('mide desde que el cliente reportó, no desde que se registró', () {
      final c = caso(
        reportado: DateTime(2026, 8, 31, 9),
        resuelto: DateTime(2026, 9, 1, 9),
      );
      expect(resolutionTime(c), const Duration(days: 1));
    });

    test('un resuelto antes de reportado cuenta como cero, no negativo', () {
      // Dato sucio: un caso registrado con fecha de reporte posterior a su
      // resolución. Dejarlo negativo le restaría tiempo al promedio de todos
      // los demás y lo haría ver mejor de lo que es.
      final c = caso(
        reportado: DateTime(2026, 9, 2),
        resuelto: DateTime(2026, 9, 1),
      );
      expect(resolutionTime(c), Duration.zero);
    });
  });

  group('averageResolutionTime', () {
    test('sin casos resueltos devuelve null, no cero', () {
      // "Todavía no hay con qué calcularlo" y "se resuelven al instante" son
      // cosas distintas; un cero las confundiría en pantalla.
      expect(averageResolutionTime([caso(reportado: lunes)]), isNull);
    });

    test('promedia sólo los resueltos e ignora los abiertos', () {
      final casos = [
        caso(reportado: lunes, resuelto: lunes.add(const Duration(days: 2))),
        caso(reportado: lunes, resuelto: lunes.add(const Duration(days: 4))),
        caso(reportado: lunes), // abierto: no debe entrar al promedio
      ];
      expect(averageResolutionTime(casos), const Duration(days: 3));
    });
  });

  group('oldestOpenDays', () {
    test('ignora los resueltos por viejos que sean', () {
      final casos = [
        caso(reportado: DateTime(2020, 1, 1), resuelto: DateTime(2020, 1, 2)),
      ];
      expect(oldestOpenDays(casos), isNull);
    });

    test('devuelve los días del abierto más viejo', () {
      final hace10 = DateTime.now().subtract(const Duration(days: 10));
      final hace3 = DateTime.now().subtract(const Duration(days: 3));
      expect(
        oldestOpenDays([caso(reportado: hace3), caso(reportado: hace10)]),
        10,
      );
    });
  });

  group('inPeriod', () {
    test('los dos extremos están incluidos', () {
      final a = DateTime(2026, 9, 1);
      final b = DateTime(2026, 9, 6);
      expect(inPeriod(a, a, b), isTrue);
      expect(inPeriod(b, a, b), isTrue);
      expect(inPeriod(DateTime(2026, 8, 31), a, b), isFalse);
      expect(inPeriod(DateTime(2026, 9, 7), a, b), isFalse);
    });

    test('la hora no saca a un caso de su día', () {
      // Un caso reportado a las 23:50 del último día del periodo tiene que
      // entrar: comparar con la hora puesta lo dejaría fuera.
      expect(
        inPeriod(
          DateTime(2026, 9, 6, 23, 50),
          DateTime(2026, 9, 1),
          DateTime(2026, 9, 6),
        ),
        isTrue,
      );
    });
  });

  group('dailyFlow', () {
    test('devuelve un día por cada uno del periodo, en orden', () {
      final f = dailyFlow(
        [],
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 6),
      );
      expect(f.length, 6);
      expect(f.first.day, DateTime(2026, 9, 1));
      expect(f.last.day, DateTime(2026, 9, 6));
    });

    test('cruza el cambio de mes sin saltarse ni repetir días', () {
      final f = dailyFlow(
        [],
        start: DateTime(2026, 8, 30),
        end: DateTime(2026, 9, 2),
      );
      expect(f.map((d) => d.day), [
        DateTime(2026, 8, 30),
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 2),
      ]);
    });

    test('un periodo de un solo día devuelve ese día', () {
      final f = dailyFlow(
        [],
        start: DateTime(2026, 9, 6),
        end: DateTime(2026, 9, 6),
      );
      expect(f.length, 1);
    });

    test('un periodo al revés no devuelve nada en vez de colgarse', () {
      // El bucle avanza hasta pasar el final; con el final antes del inicio y
      // sin esta guarda no terminaría nunca.
      final f = dailyFlow(
        [],
        start: DateTime(2026, 9, 6),
        end: DateTime(2026, 9, 1),
      );
      expect(f, isEmpty);
    });

    test('los días sin nada valen cero, no se saltan', () {
      final f = dailyFlow(
        [caso(reportado: DateTime(2026, 9, 3))],
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 4),
      );
      expect(f.map((d) => d.opened), [0, 0, 1, 0]);
    });

    test('entra por fecha de reporte y sale por fecha de resolución', () {
      // El error fácil sería contar las dos series por la misma fecha: las
      // líneas se moverían juntas y el gráfico no diría nada.
      final c = caso(
        reportado: DateTime(2026, 9, 1, 10),
        resuelto: DateTime(2026, 9, 4, 16),
      );
      final f = dailyFlow(
        [c],
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 4),
      );
      expect(f.map((d) => d.opened), [1, 0, 0, 0]);
      expect(f.map((d) => d.resolved), [0, 0, 0, 1]);
    });

    test('lo que queda fuera del periodo no se cuenta', () {
      final viejo = caso(reportado: DateTime(2026, 1, 1));
      final f = dailyFlow(
        [viejo],
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 6),
      );
      expect(f.every((d) => d.opened == 0), isTrue);
    });
  });

  group('reportedIn / resolvedIn', () {
    test('un caso resuelto en el periodo cuenta aunque entrara antes', () {
      // Es lo que hace honesta la cifra de "resueltos": el trabajo sacado este
      // mes incluye casos que llegaron el mes pasado.
      final c = caso(
        reportado: DateTime(2026, 7, 10),
        resuelto: DateTime(2026, 9, 3),
      );
      final desde = DateTime(2026, 9, 1);
      final hasta = DateTime(2026, 9, 6);
      expect(resolvedIn([c], desde, hasta), hasLength(1));
      expect(reportedIn([c], desde, hasta), isEmpty);
    });

    test('un caso abierto nunca aparece entre los resueltos', () {
      final c = caso(reportado: DateTime(2026, 9, 2));
      expect(
        resolvedIn([c], DateTime(2026, 9, 1), DateTime(2026, 9, 6)),
        isEmpty,
      );
    });
  });

  group('formatDay', () {
    test('día y mes abreviado', () {
      expect(formatDay(DateTime(2026, 9, 6)), '6 sep');
      expect(formatDay(DateTime(2026, 1, 31)), '31 ene');
    });
  });

  group('formatResolutionTime', () {
    test('menos de una hora en minutos', () {
      expect(formatResolutionTime(const Duration(minutes: 42)), '42 min');
    });

    test('menos de un día en horas', () {
      expect(formatResolutionTime(const Duration(hours: 5)), '5 h');
    });

    test('un día y medio no se redondea a "1 día"', () {
      // Media jornada de diferencia es justo lo que se quiere vigilar.
      expect(formatResolutionTime(const Duration(hours: 36)), '1,5 días');
    });
  });
}
