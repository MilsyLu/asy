/// Qué pasa con el recordatorio cuando la tarea cambia de día o de hora.
///
/// La tarea guarda el recordatorio como un **instante**, no como "15 minutos
/// antes". Eso basta mientras la tarea no se mueva; en cuanto se mueve, el
/// instante se queda donde estaba y suena el día viejo: una instalación de
/// hoy a las 4:00 p. m. reprogramada para dentro de cuatro días seguía
/// avisando hoy a las 3:45.
///
/// Lo que la persona eligió no fue "las 3:45 de hoy", fue "quince minutos
/// antes". Eso es lo que se conserva aquí: la distancia entre la tarea y su
/// aviso. Funciona igual para los tiempos de la lista y para uno
/// personalizado, porque en los dos casos la distancia es la misma idea.
library;

/// El recordatorio después de mover la tarea.
class RecordatorioMovido {
  const RecordatorioMovido({required this.instante, required this.seQuito});

  /// Cuándo debe sonar ahora. `null` si no había, o si ya no alcanza.
  final DateTime? instante;

  /// Había un recordatorio y hubo que quitarlo porque su nuevo momento ya
  /// pasó. Quien llama avisa: quitarlo en silencio sería peor que el error
  /// que esto corrige.
  final bool seQuito;

  /// No había recordatorio, o no hay con qué calcular: se deja como estaba.
  static const RecordatorioMovido sinCambio = RecordatorioMovido(
    instante: null,
    seQuito: false,
  );
}

/// Mueve [recordatorioActual] la misma distancia que se movió la tarea.
///
/// [momentoAnterior] y [momentoNuevo] son la fecha+hora de la tarea antes y
/// después del cambio. Si falta alguno de los tres datos no hay nada que
/// calcular y se devuelve el recordatorio tal como estaba.
///
/// [ahora] existe para las pruebas; en la aplicación se omite.
RecordatorioMovido moverRecordatorio({
  required DateTime? recordatorioActual,
  required DateTime? momentoAnterior,
  required DateTime? momentoNuevo,
  DateTime? ahora,
}) {
  if (recordatorioActual == null ||
      momentoAnterior == null ||
      momentoNuevo == null) {
    return RecordatorioMovido(instante: recordatorioActual, seQuito: false);
  }

  final distancia = momentoAnterior.difference(recordatorioActual);
  final nuevo = momentoNuevo.subtract(distancia);

  // Un recordatorio en el pasado no avisa de nada: el reloj del servidor lo
  // ve vencido y lo manda de una, así que sonaría en el mismo momento de
  // guardar. Mejor decirlo que mandar un aviso inútil.
  if (!nuevo.isAfter(ahora ?? DateTime.now())) {
    return const RecordatorioMovido(instante: null, seQuito: true);
  }

  return RecordatorioMovido(instante: nuevo, seQuito: false);
}
