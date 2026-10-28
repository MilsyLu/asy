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

  /// Day + month only, no year, e.g. "09/06" — used for compact chart axis
  /// labels where "Tendencia de tareas"' caption above the chart already
  /// states the full range/year.
  static String formatDayMonth(DateTime date) {
    return DateFormat('dd/MM').format(date);
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

  /// La fecha sin la hora: útil para comparar días sin que las 00:01 y las
  /// 23:59 del mismo día parezcan distintas.
  static DateTime soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

  /// "Buenos días" / "Buenas tardes" / "Buenas noches", según la hora.
  ///
  /// Vive aquí porque estaba escrito dos veces —en la Agenda diaria y en la
  /// barra superior— y las dos copias ya no coincidían: una cambiaba a
  /// "noches" a las 18 y la otra a las 19.
  ///
  /// Recibe la hora en vez de leerla sola para poder probarla, y porque el
  /// error que arregló fue justamente ése: la Agenda le pasaba `today`, que
  /// es el *comienzo* del día y por tanto siempre las 00:00. Caía en el
  /// último caso y saludaba "Buenas noches" a las cuatro de la tarde.
  static String saludoDelDia(DateTime ahora) {
    final h = ahora.hour;
    if (h >= 6 && h < 12) return 'Buenos días';
    if (h >= 12 && h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  /// Formats a [DateTime] as 12-hour time with Spanish am/pm, e.g. "07:59 a. m.".
  static String formatTime12h(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute;
    final ampm = h < 12 ? 'a. m.' : 'p. m.';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${h12.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $ampm';
  }
}
