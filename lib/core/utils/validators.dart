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

  /// Removes everything except digits, keeping a leading '+' (if any).
  /// E.g. "300 225 7755" -> "3002257755", "+57 300 225 7755" -> "+573002257755".
  static String cleanPhone(String value) {
    final trimmed = value.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return trimmed.startsWith('+') ? '+$digits' : digits;
  }

  /// Formats a phone number for display by grouping its last 10 digits as
  /// "XXX XXX XXXX" and showing any leading country code separately.
  /// E.g. "3002257755" -> "300 225 7755", "+573002257755" -> "+57 300 225 7755".
  static String formatPhone(String value) {
    final cleaned = cleanPhone(value);
    final hasPlus = cleaned.startsWith('+');
    final digits = hasPlus ? cleaned.substring(1) : cleaned;
    if (digits.length < 10) return cleaned;
    final local = digits.substring(digits.length - 10);
    final countryCode = digits.substring(0, digits.length - 10);
    final formattedLocal =
        '${local.substring(0, 3)} ${local.substring(3, 6)} ${local.substring(6)}';
    return countryCode.isEmpty ? formattedLocal : '+$countryCode $formattedLocal';
  }

  /// Allows only digits, '+' and spaces, and requires at least 10 digits —
  /// with or without a country code (e.g. "3002257755" or "+573002257755").
  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (!_phoneRegex.hasMatch(trimmed)) {
      return 'Solo se permiten números, "+" y espacios';
    }
    final cleaned = cleanPhone(trimmed);
    final digits = cleaned.startsWith('+') ? cleaned.substring(1) : cleaned;
    if (digits.length < 10) {
      return 'El teléfono debe tener al menos 10 dígitos';
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
