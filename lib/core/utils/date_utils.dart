import 'package:intl/intl.dart';

/// Date helpers used throughout the app.
class AppDateUtils {
  AppDateUtils._();

  /// Formats a [DateTime] as `YYYY-MM-DD` for use as a Firestore query field.
  static String formatDateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// Parses a `YYYY-MM-DD` string back into a [DateTime] (local, midnight).
  static DateTime parseDateKey(String dateKey) {
    return DateFormat('yyyy-MM-dd').parse(dateKey);
  }

  /// Returns true if [a] and [b] fall on the same calendar day.
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Human readable date, e.g. "lun. 9 jun. 2026".
  static String formatHumanDate(DateTime date) {
    return DateFormat('EEEE d MMMM yyyy', 'es').format(date);
  }

  /// Header date without year, e.g. "viernes 12 de junio". Callers
  /// capitalize the first letter for display.
  static String formatHeaderDate(DateTime date) {
    return DateFormat("EEEE d 'de' MMMM", 'es').format(date);
  }

  /// Short date, e.g. "09/06/2026".
  static String formatShortDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// Formats a [DateTime] as "HH:mm".
  static String formatHour(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  /// Formats a nullable [DateTime] as a readable date+time, or "-" if null.
  static String formatDateTimeOrDash(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd/MM/yyyy HH:mm').format(date);
  }
}
