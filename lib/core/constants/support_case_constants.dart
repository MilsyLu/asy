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
  static const String esperandoCliente = 'Esperando cliente';
  static const String resuelto = 'Resuelto';

  // "Cerrado" (a separate closed state) was removed — Michel felt it was
  // practically the same as "Resuelto" and preferred one clear state
  // instead of two similar ones.
  static const List<String> all = [nuevo, enProceso, esperandoCliente, resuelto];

  static const List<String> openStates = [nuevo, enProceso, esperandoCliente];
  static const List<String> closedStates = [resuelto];

  static const Map<String, Color> colors = {
    nuevo: Colors.blue,
    enProceso: Colors.purple,
    esperandoCliente: Colors.teal,
    resuelto: Colors.green,
  };

  static Color colorFor(String status) => colors[status] ?? Colors.grey;

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
