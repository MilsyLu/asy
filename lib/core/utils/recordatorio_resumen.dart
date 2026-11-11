import 'date_utils.dart';

/// Cómo se lee el recordatorio de una tarea, en una línea.
///
/// Una tarea podía tener recordatorio puesto y no se notaba en ninguna
/// parte: ni en el calendario, ni en la agenda, ni en la vista por
/// encargado. Había que abrir la tarea para enterarse, así que en la
/// práctica uno no sabía si iba a sonar o no.
///
/// Devuelve null cuando no hay recordatorio, para que quien la use
/// sencillamente no dibuje la línea.
///
/// La hora sola cuando cae el mismo día de la tarea —que es lo normal— y con
/// la fecha cuando es otro día, porque ahí "09:30" a secas no dice nada.
/// [enviado] es `reminderSent`, que marca la función de la nube cuando ya
/// avisó: una vez sonó, lo útil es saber que sonó, no esperarlo.
String? resumenRecordatorio({
  required DateTime? recordatorio,
  required bool enviado,
  required DateTime fechaTarea,
}) {
  if (recordatorio == null) return null;

  final mismoDia =
      AppDateUtils.soloDia(recordatorio) == AppDateUtils.soloDia(fechaTarea);
  final cuando = mismoDia
      ? AppDateUtils.formatHour(recordatorio)
      : '${AppDateUtils.formatDayMonth(recordatorio)} '
            '${AppDateUtils.formatHour(recordatorio)}';

  return enviado ? 'Recordatorio enviado · $cuando' : 'Recordatorio: $cuando';
}
