/// User roles, stored in `users/{userId}.role`.
class AppRoles {
  AppRoles._();

  static const String superAdmin = 'super_admin';
  static const String trabajadorNormal = 'trabajador_normal';
}

/// Well-known status names used by reports & business logic.
/// The actual documents live in the `statuses` collection (admin-editable),
/// but these names are used to match status documents for special handling.
class AppStatusNames {
  AppStatusNames._();

  static const String pendiente = 'Pendiente';
  static const String completada = 'Completada';
  static const String reprogramada = 'Reprogramada';
  static const String cancelada = 'Cancelada';
}

/// Well-known task type names used by reports & business logic.
class AppTaskTypeNames {
  AppTaskTypeNames._();

  static const String instalacion = 'Instalación';
}

class AppConstants {
  AppConstants._();

  static const String appName = 'CheCu';
  static const String appTagline = 'Chequeo y Cumplimiento de tareas';
  static const String appVersion = '1.0';
  static const String appDeveloper = 'CustoDesk 2026';
}
