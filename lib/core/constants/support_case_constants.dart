import 'package:flutter/material.dart';

/// Fixed priority levels for a support case — a small, well-known set
/// (unlike task types/statuses, this isn't an admin-editable catalog).
class SupportCasePriority {
  SupportCasePriority._();

  static const String baja = 'Baja';
  static const String media = 'Media';
  static const String alta = 'Alta';
  static const String critica = 'Crítica';

  static const List<String> all = [baja, media, alta, critica];

  static const Map<String, Color> colors = {
    baja: Colors.green,
    media: Colors.amber,
    alta: Colors.orange,
    critica: Colors.red,
  };

  static Color colorFor(String priority) => colors[priority] ?? Colors.grey;
}

/// Fixed lifecycle states for a support case.
class SupportCaseStatus {
  SupportCaseStatus._();

  static const String nuevo = 'Nuevo';
  static const String enProceso = 'En proceso';

  /// El caso ya se escaló al equipo técnico y se espera respuesta de ellos.
  ///
  /// Va entre "En proceso" y "Esperando cliente" porque es el mismo tipo de
  /// espera, sólo que del otro lado: uno espera a tecnología, el otro al
  /// cliente. Sigue contando como abierto — el reloj de días no se detiene
  /// porque el caso esté en manos de otro.
  static const String reportado = 'Reportado';
  static const String esperandoCliente = 'Esperando cliente';
  static const String resuelto = 'Resuelto';

  // "Cerrado" (a separate closed state) was removed — Michel felt it was
  // practically the same as "Resuelto" and preferred one clear state
  // instead of two similar ones.
  static const List<String> all = [
    nuevo,
    enProceso,
    reportado,
    esperandoCliente,
    resuelto,
  ];

  static const List<String> openStates = [
    nuevo,
    enProceso,
    reportado,
    esperandoCliente,
  ];
  static const List<String> closedStates = [resuelto];

  static const Map<String, Color> colors = {
    nuevo: Colors.blue,
    enProceso: Colors.purple,
    // Naranja: el caso está parado esperando a alguien de afuera. Es el mismo
    // aviso que dan los días acumulados, y se distingue de un vistazo del
    // morado de "En seguimiento", que sí está en manos nuestras.
    reportado: Colors.orange,
    esperandoCliente: Colors.teal,
    resuelto: Colors.green,
  };

  static Color colorFor(String status) => colors[status] ?? Colors.grey;

  /// Lo que ve el usuario para un estado guardado.
  ///
  /// El valor de [nuevo] es la cadena `'Nuevo'` y así está escrito en cada
  /// documento de `supportCases`, además de en `checkSupportCaseReminders.js`,
  /// que decide a quién recordarle. Renombrar la constante rompería los dos.
  /// Así que el valor se queda y solo cambia la etiqueta.
  ///
  /// Y cambia porque mentía: esa columna no tiene casos nuevos, tiene casos
  /// sin empezar — Michel encontró ahí casos de once días. "Pendiente" es lo
  /// que la columna siempre quiso decir. De hecho el filtro rápido de esa
  /// misma pantalla ya se llamaba "Pendientes" y filtraba exactamente por este
  /// estado: la pantalla venía llamando a lo mismo de dos formas distintas.
  /// Lo mismo vale para [enProceso], que Michel pidió llamar "En
  /// seguimiento": "En proceso" no distinguía nada —todo caso abierto está en
  /// proceso de algo— mientras que un caso en seguimiento es uno que alguien
  /// está empujando ahora mismo. El valor guardado sigue siendo `'En
  /// proceso'`, que es lo que ya dice cada documento y lo que lee
  /// `supportCaseStatus.js` para saber qué sigue abierto.
  static String labelFor(String status) => switch (status) {
    nuevo => 'Pendiente',
    enProceso => 'En seguimiento',
    _ => status,
  };

  /// Igual, para un encabezado de columna que agrupa varios.
  static String columnLabelFor(String status) => switch (status) {
    nuevo => 'Pendientes',
    enProceso => 'En seguimiento',
    _ => status,
  };

  static bool isOpen(String status) => openStates.contains(status);
}

/// "Días sin resolver" color scale — same thresholds Michel specified:
/// 0-2 verde, 3-5 amarillo, 6-10 naranja, >10 rojo. Shared by the list row's
/// days badge and the case detail header so both always agree.
Color colorForDaysOpen(int days) {
  if (days <= 2) return Colors.green;
  if (days <= 5) return Colors.amber;
  if (days <= 10) return Colors.orange;
  return Colors.red;
}
