/// Form field validators shared across the app.
class Validators {
  Validators._();

  static final RegExp _phoneRegex = RegExp(r'^[0-9+\s]+$');
  static final RegExp _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? required(String? value, {String fieldName = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName es requerido';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'El email es requerido';
    if (!_emailRegex.hasMatch(value.trim())) return 'Email inválido';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'La contraseña es requerida';
    if (value.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }

  /// Allows only digits, '+' and spaces (e.g. "+56 9 1234 5678").
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El teléfono es requerido';
    }
    if (!_phoneRegex.hasMatch(value.trim())) {
      return 'Solo se permiten números, "+" y espacios';
    }
    return null;
  }

  /// Validates that a reminder DateTime is strictly before the task's
  /// scheduled DateTime (date + "HH:MM" hour).
  ///
  /// Example: if the task is at 14:00, the latest valid reminder is 13:59
  /// of the same day. Reminders on a previous day are always valid.
  static bool isReminderValid({
    required DateTime taskDate,
    required String taskHour,
    DateTime? reminderDateTime,
  }) {
    if (reminderDateTime == null) return true;
    final parts = taskHour.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final taskDateTime = DateTime(
      taskDate.year,
      taskDate.month,
      taskDate.day,
      hour,
      minute,
    );
    return reminderDateTime.isBefore(taskDateTime);
  }
}
