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

/// Un día del gráfico de entradas contra salidas.
class SupportDay {
  const SupportDay({
    required this.day,
    required this.opened,
    required this.resolved,
  });

  /// El día, sin hora.
  final DateTime day;

  /// Casos reportados ese día.
  final int opened;

  /// Casos resueltos ese día — no necesariamente los mismos.
  final int resolved;
}

/// [d] sin la hora.
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Si [d] cae dentro de [start]–[end], ambos días incluidos.
bool inPeriod(DateTime d, DateTime start, DateTime end) {
  final dia = dayOnly(d);
  return !dia.isBefore(dayOnly(start)) && !dia.isAfter(dayOnly(end));
}

/// Los casos reportados dentro del periodo.
List<SupportCaseModel> reportedIn(
  Iterable<SupportCaseModel> cases,
  DateTime start,
  DateTime end,
) => [
  for (final c in cases)
    if (inPeriod(c.reportedAt, start, end)) c,
];

/// Los casos resueltos dentro del periodo.
///
/// No son los mismos que [reportedIn]: un caso reportado en julio y resuelto
/// en septiembre cuenta como salida de septiembre. Contar ambas cosas por la
/// misma fecha —el error fácil— haría que las dos series se movieran juntas y
/// el gráfico no diría nada.
List<SupportCaseModel> resolvedIn(
  Iterable<SupportCaseModel> cases,
  DateTime start,
  DateTime end,
) => [
  for (final c in cases)
    if (c.resolvedAt != null && inPeriod(c.resolvedAt!, start, end)) c,
];

/// Cuántos casos entraron y cuántos se resolvieron cada día del periodo, del
/// más viejo al más reciente.
///
/// Los días sin nada aparecen en cero en vez de desaparecer: un hueco saltado
/// convierte un día muerto en una línea que sigue de largo.
List<SupportDay> dailyFlow(
  Iterable<SupportCaseModel> cases, {
  required DateTime start,
  required DateTime end,
}) {
  final desde = dayOnly(start);
  final hasta = dayOnly(end);
  if (hasta.isBefore(desde)) return const [];

  final entradas = <DateTime, int>{};
  final salidas = <DateTime, int>{};

  for (final c in cases) {
    if (inPeriod(c.reportedAt, desde, hasta)) {
      final d = dayOnly(c.reportedAt);
      entradas[d] = (entradas[d] ?? 0) + 1;
    }
    final resuelto = c.resolvedAt;
    if (resuelto != null && inPeriod(resuelto, desde, hasta)) {
      final d = dayOnly(resuelto);
      salidas[d] = (salidas[d] ?? 0) + 1;
    }
  }

  // Se avanza con aritmética de calendario y no sumando 24 horas: en un país
  // con cambio de hora, sumar días como duraciones desplaza el reloj y termina
  // saltándose o repitiendo un día.
  final dias = <SupportDay>[];
  for (
    var d = desde;
    !d.isAfter(hasta);
    d = DateTime(d.year, d.month, d.day + 1)
  ) {
    dias.add(
      SupportDay(day: d, opened: entradas[d] ?? 0, resolved: salidas[d] ?? 0),
    );
  }
  return dias;
}

const _meses = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// Un día suelto: "6 sep".
String formatDay(DateTime d) => '${d.day} ${_meses[d.month - 1]}';

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
