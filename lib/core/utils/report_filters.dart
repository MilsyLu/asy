import '../../models/task_model.dart';

/// Stands for "the ones that have none" in a dropdown whose other options are
/// ids — a task can have no team and no type, and `catalog` shows those as
/// "Sin equipo" / "Sin tipo". Without it those rows would be unreachable: no
/// option would ever select them, and they would vanish from every filtered
/// view and every export without anything saying so.
const String kSinAsignar = '__sin_asignar__';

/// What the Reportes screen is currently narrowed down to.
///
/// Kept apart from the screen so the matching rules can be tested: a filter
/// that quietly drops rows is indistinguishable from having no data, and the
/// exports read from the same filtered list, so a mistake here would leave a
/// spreadsheet missing rows nobody would think to look for.
class ReportFilters {
  const ReportFilters({
    this.search = '',
    this.groupId,
    this.userId,
    this.statusId,
    this.taskTypeId,
  });

  /// Free text, matched against the client's name and phone.
  final String search;

  /// Null means "todos" — an explicit id narrows to it.
  final String? groupId;
  final String? userId;
  final String? statusId;
  final String? taskTypeId;

  bool get isEmpty =>
      search.trim().isEmpty &&
      groupId == null &&
      userId == null &&
      statusId == null &&
      taskTypeId == null;

  ReportFilters copyWith({
    String? search,
    String? groupId,
    String? userId,
    String? statusId,
    String? taskTypeId,
    bool clearGroup = false,
    bool clearUser = false,
    bool clearStatus = false,
    bool clearTaskType = false,
  }) {
    return ReportFilters(
      search: search ?? this.search,
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      userId: clearUser ? null : (userId ?? this.userId),
      statusId: clearStatus ? null : (statusId ?? this.statusId),
      taskTypeId: clearTaskType ? null : (taskTypeId ?? this.taskTypeId),
    );
  }

  bool matches(TaskModel task) {
    if (!_matchesId(groupId, task.groupId)) return false;
    if (userId != null && task.assignedUserId != userId) return false;
    if (statusId != null && task.statusId != statusId) return false;
    if (!_matchesId(taskTypeId, task.taskTypeId)) return false;

    final query = search.trim();
    if (query.isEmpty) return true;

    if (_fold(task.clientName).contains(_fold(query))) return true;

    // Phones are typed with spaces, dashes and sometimes a country code, and
    // searched the same way — comparing them as written almost never matches.
    final digits = _digits(query);
    if (digits.isNotEmpty && _digits(task.clientPhone).contains(digits)) {
      return true;
    }

    return false;
  }

  /// Null [selected] means "todos"; [kSinAsignar] means "the ones with none".
  static bool _matchesId(String? selected, String? actual) {
    if (selected == null) return true;
    if (selected == kSinAsignar) return actual == null;
    return actual == selected;
  }

  List<TaskModel> apply(List<TaskModel> tasks) =>
      isEmpty ? tasks : tasks.where(matches).toList();

  /// The active filters spelled out, for the export to carry.
  ///
  /// A workbook outlives the screen it came from. Without this, a file opened
  /// three weeks later shows twelve tasks and no way to tell whether that was
  /// the whole month or one team's slice of it — and the two get read the same
  /// way. [nameOf] resolves each id, since the ids mean nothing to a reader.
  List<String> describe({
    required String Function(String?) groupName,
    required String Function(String?) userName,
    required String Function(String?) statusName,
    required String Function(String?) taskTypeName,
  }) {
    String label(String id, String Function(String?) nameOf) =>
        nameOf(id == kSinAsignar ? null : id);

    return [
      if (search.trim().isNotEmpty) 'Búsqueda: "${search.trim()}"',
      if (groupId != null) 'Equipo: ${label(groupId!, groupName)}',
      if (userId != null) 'Encargado: ${label(userId!, userName)}',
      if (statusId != null) 'Estado: ${label(statusId!, statusName)}',
      if (taskTypeId != null) 'Tipo: ${label(taskTypeId!, taskTypeName)}',
    ];
  }
}

/// Lowercase and strip the accents Spanish names carry, so searching "cafe"
/// finds "Café" and "panaderia" finds "panadería". Nobody types the accent
/// when they are looking for something.
String _fold(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    buffer.write(
      _sinAcento[String.fromCharCode(rune)] ?? String.fromCharCode(rune),
    );
  }
  return buffer.toString();
}

const _sinAcento = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
};

String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');
