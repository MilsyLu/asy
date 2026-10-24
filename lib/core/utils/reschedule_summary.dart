import '../../models/task_model.dart';

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

/// "5 oct" a partir de una clave "YYYY-MM-DD".
///
/// Sin parsear a `DateTime`: la clave ya viene partida y así una fecha
/// malformada devuelve el texto crudo en vez de reventar en pantalla.
String shortDateKey(String dateKey) {
  final p = dateKey.split('-');
  if (p.length != 3) return dateKey;
  final mes = int.tryParse(p[1]);
  final dia = int.tryParse(p[2]);
  if (mes == null || dia == null || mes < 1 || mes > 12) return dateKey;
  return '$dia ${_meses[mes - 1]}';
}

/// La frase que explica una reprogramación, o `null` si la tarea nunca se
/// movió.
///
/// Existe porque "Reprogramada" a secas no dice nada de lo que uno quiere
/// saber: de qué fecha venía, y si de verdad cambió de día. Michel lo planteó
/// mirando el calendario — "¿qué hacen estas tareas en el 7 de octubre si
/// están reprogramadas?". La respuesta era que el 7 de octubre ES su fecha
/// nueva, y eso no se leía por ninguna parte.
///
/// Distingue el caso que más confunde: reprogramar **sólo la hora** también
/// marca la tarea como "Reprogramada", así que una tarea que nunca cambió de
/// día parece haberse movido a otro.
///
/// Las tareas anteriores a que se guardara el historial no tienen de dónde:
/// su fecha vieja ya se había sobrescrito. Se dice así, en vez de callarlo.
String? rescheduleSummary({
  required List<RescheduleEntry> history,
  required int rescheduledCount,
  required String currentDate,
}) {
  if (rescheduledCount <= 0 && history.isEmpty) return null;

  final veces = rescheduledCount > history.length
      ? rescheduledCount
      : history.length;
  final sufijo = veces > 1 ? ' · $veces veces' : '';

  if (history.isEmpty) {
    return 'Sin registro de la fecha anterior$sufijo';
  }

  final ultima = history.last;
  if (ultima.fromDate == currentDate) {
    return 'Antes a las ${ultima.fromHour}, el mismo día$sufijo';
  }
  return 'Antes: ${shortDateKey(ultima.fromDate)} '
      '${ultima.fromHour}$sufijo';
}

/// El recorrido completo de una tarea movida, para la ventana de detalle.
///
/// Devuelve la cadena de fechas por las que pasó, terminando en la actual:
/// `1 oct 08:00 → 5 oct 10:00 → 7 oct 15:30`. Cada eslabón es el "desde" de
/// una reprogramación, y el último es dónde está hoy — así el "hasta" de cada
/// salto es el "desde" del siguiente y no hay que repetir fechas.
///
/// Para una tarea movida antes de que se guardara el historial no hay
/// recorrido que mostrar: se dice cuántas veces se movió y que las fechas no
/// quedaron.
String? rescheduleChain({
  required List<RescheduleEntry> history,
  required int rescheduledCount,
  required String currentDate,
  required String currentHour,
}) {
  if (rescheduledCount <= 0 && history.isEmpty) return null;

  if (history.isEmpty) {
    final veces = rescheduledCount == 1 ? 'una vez' : '$rescheduledCount veces';
    return 'Se movió $veces. Las fechas anteriores no quedaron registradas '
        '(la tarea se reprogramó antes de que se guardaran).';
  }

  final pasos = [
    for (final e in history) '${shortDateKey(e.fromDate)} ${e.fromHour}',
    '${shortDateKey(currentDate)} $currentHour',
  ];
  return pasos.join('  →  ');
}
