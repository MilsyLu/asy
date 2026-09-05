import '../constants/support_case_constants.dart';
import '../../models/support_case_model.dart';

/// Las cuentas del Resumen de Casos de Soporte, separadas de la pantalla.
///
/// Funciones libres y sin Firestore por la misma razón que las métricas del
/// Dashboard: así las prueba una prueba de verdad. Una cuenta enterrada dentro
/// de un `build` sólo se puede comprobar mirándola, y mirar no distingue un
/// promedio bien calculado de uno que divide por el número equivocado.

/// Cuánto tardó en resolverse un caso, o `null` si sigue abierto.
///
/// Se mide desde [SupportCaseModel.reportedAt] —cuándo lo reportó el cliente—
/// y no desde `createdAt`, que es cuándo alguien alcanzó a registrarlo en
/// CheCu. Para el cliente el reloj arranca cuando llamó, no cuando lo
/// anotamos, y esa diferencia es justo la que un indicador de servicio no
/// debería esconder.
Duration? resolutionTime(SupportCaseModel c) {
  final resolved = c.resolvedAt;
  if (resolved == null) return null;
  final d = resolved.difference(c.reportedAt);
  // Un caso registrado después de resolverse daría negativo. Es dato sucio,
  // no un caso instantáneo, pero contarlo como cero es mejor que restarle
  // tiempo al promedio de todos los demás.
  return d.isNegative ? Duration.zero : d;
}

/// Días que lleva abierto el caso más viejo sin resolver, o `null` si no hay
/// ninguno abierto.
int? oldestOpenDays(Iterable<SupportCaseModel> cases) {
  var mayor = -1;
  for (final c in cases) {
    if (!SupportCaseStatus.isOpen(c.status)) continue;
    final dias = c.daysOpen();
    if (dias > mayor) mayor = dias;
  }
  return mayor < 0 ? null : mayor;
}

/// Promedio de resolución de los casos ya resueltos, o `null` si no hay
/// ninguno todavía.
///
/// `null` y no `Duration.zero`: "aún no hay con qué calcularlo" y "se resuelven
/// al instante" son cosas distintas, y la pantalla las dibuja distinto.
Duration? averageResolutionTime(Iterable<SupportCaseModel> cases) {
  var suma = 0;
  var n = 0;
  for (final c in cases) {
    final t = resolutionTime(c);
    if (t == null) continue;
    suma += t.inMinutes;
    n++;
  }
  return n == 0 ? null : Duration(minutes: suma ~/ n);
}

/// Una semana del gráfico de entradas contra salidas.
class SupportWeek {
  const SupportWeek({
    required this.start,
    required this.opened,
    required this.resolved,
  });

  /// Lunes de la semana.
  final DateTime start;

  /// Casos reportados dentro de la semana.
  final int opened;

  /// Casos resueltos dentro de la semana — no necesariamente los mismos.
  final int resolved;
}

/// El lunes de la semana a la que pertenece [d], sin hora.
DateTime weekStart(DateTime d) {
  final dia = DateTime(d.year, d.month, d.day);
  return dia.subtract(Duration(days: dia.weekday - DateTime.monday));
}

/// Cuántos casos entraron y cuántos se resolvieron en cada una de las últimas
/// [weeks] semanas, de la más vieja a la más reciente.
///
/// Las dos series se cuentan por fechas distintas a propósito: un caso entra la
/// semana en que lo reportaron y sale la semana en que se resolvió, que casi
/// nunca es la misma. Contar ambas por la fecha de creación —el error fácil—
/// dibujaría dos líneas que se mueven juntas y no dirían nada.
///
/// Las semanas sin nada aparecen en cero en vez de desaparecer: un hueco
/// saltado convierte una semana muerta en una línea que sigue de largo.
List<SupportWeek> weeklyFlow(
  Iterable<SupportCaseModel> cases, {
  required DateTime now,
  int weeks = 8,
}) {
  final actual = weekStart(now);
  final primera = actual.subtract(Duration(days: 7 * (weeks - 1)));

  final entradas = <DateTime, int>{};
  final salidas = <DateTime, int>{};

  for (final c in cases) {
    final entrada = weekStart(c.reportedAt);
    if (!entrada.isBefore(primera) && !entrada.isAfter(actual)) {
      entradas[entrada] = (entradas[entrada] ?? 0) + 1;
    }
    final resuelto = c.resolvedAt;
    if (resuelto != null) {
      final salida = weekStart(resuelto);
      if (!salida.isBefore(primera) && !salida.isAfter(actual)) {
        salidas[salida] = (salidas[salida] ?? 0) + 1;
      }
    }
  }

  return [
    for (var i = 0; i < weeks; i++)
      () {
        final semana = primera.add(Duration(days: 7 * i));
        return SupportWeek(
          start: semana,
          opened: entradas[semana] ?? 0,
          resolved: salidas[semana] ?? 0,
        );
      }(),
  ];
}

/// Texto corto para una duración: "3 h", "2,4 días".
///
/// Días con un decimal porque la diferencia entre 1,2 y 1,8 días es la mitad
/// de una jornada — redondear a "1 día" borra justamente lo que se quiere
/// vigilar. Por debajo de un día se dice en horas, que es como se habla.
String formatResolutionTime(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours} h';
  final dias = d.inMinutes / (60 * 24);
  return '${dias.toStringAsFixed(1).replaceAll('.', ',')} días';
}
