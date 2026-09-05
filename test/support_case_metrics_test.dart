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
        caso(
          reportado: DateTime(2020, 1, 1),
          resuelto: DateTime(2020, 1, 2),
        ),
      ];
      expect(oldestOpenDays(casos), isNull);
    });

    test('devuelve los días del abierto más viejo', () {
      final hace10 = DateTime.now().subtract(const Duration(days: 10));
      final hace3 = DateTime.now().subtract(const Duration(days: 3));
      expect(oldestOpenDays([caso(reportado: hace3), caso(reportado: hace10)]),
          10);
    });
  });

  group('weekStart', () {
    test('cualquier día de la semana cae en su lunes', () {
      for (var i = 0; i < 7; i++) {
        expect(weekStart(lunes.add(Duration(days: i))), lunes);
      }
    });

    test('el domingo pertenece a la semana que termina, no a la siguiente', () {
      expect(weekStart(DateTime(2026, 8, 30)), DateTime(2026, 8, 24));
    });

    test('descarta la hora', () {
      expect(weekStart(DateTime(2026, 9, 2, 23, 59)), lunes);
    });
  });

  group('weeklyFlow', () {
    test('devuelve una semana por cada una pedida, en orden', () {
      final f = weeklyFlow([], now: lunes, weeks: 4);
      expect(f.length, 4);
      expect(f.first.start, DateTime(2026, 8, 10));
      expect(f.last.start, lunes);
    });

    test('las semanas sin nada valen cero, no se saltan', () {
      // Saltarse una semana muerta haría que la línea siguiera de largo como
      // si no hubiera pasado nada raro. El cero es el dato.
      final f = weeklyFlow([caso(reportado: lunes)], now: lunes, weeks: 3);
      expect(f.map((w) => w.opened), [0, 0, 1]);
    });

    test('entra por fecha de reporte y sale por fecha de resolución', () {
      // El error fácil sería contar las dos series por la misma fecha: las
      // líneas se moverían juntas y el gráfico no diría nada.
      final c = caso(
        reportado: DateTime(2026, 8, 25), // semana del 24
        resuelto: DateTime(2026, 9, 2), // semana del 31
      );
      final f = weeklyFlow([c], now: lunes, weeks: 2);
      expect(f[0].start, DateTime(2026, 8, 24));
      expect(f[0].opened, 1);
      expect(f[0].resolved, 0);
      expect(f[1].opened, 0);
      expect(f[1].resolved, 1);
    });

    test('lo que queda fuera de la ventana no se cuenta', () {
      final viejo = caso(reportado: DateTime(2026, 1, 1));
      final f = weeklyFlow([viejo], now: lunes, weeks: 4);
      expect(f.every((w) => w.opened == 0), isTrue);
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
