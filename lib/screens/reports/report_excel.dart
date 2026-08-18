import 'package:excel/excel.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/excel_export.dart';
import '../../core/utils/file_delivery.dart';
import '../../core/utils/excel_tables.dart';
import '../../core/utils/report_metrics.dart';
import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/catalog_provider.dart';

/// Builds and delivers the Reportes workbook.
///
/// Four sheets rather than one dump, because Michel's question was not "give
/// me the rows" — a list of clients with name and phone is the address book he
/// already sees on screen. What a report has to answer is *how much*: which
/// clients were served most, who is idle, how many were cancelled. So every
/// list carries its numbers, and the ones that were only ever in the app —
/// when a task was created, when it was completed, who rescheduled it — come
/// out too. They were always stored; they just never left.
///
/// Everything here describes the filtered list the screen is showing. The
/// Resumen sheet spells the filters out, so a workbook that left CheCu three
/// weeks ago can still say what it was a report *of*.
Future<void> exportReportExcel({
  required List<TaskModel> tasks,
  required CatalogProvider catalog,
  required DateTime start,
  required DateTime end,
  required String generatedBy,
  required List<String> activeFilters,
}) {
  final excel = Excel.createExcel();

  _buildResumen(
    excel,
    tasks: tasks,
    catalog: catalog,
    start: start,
    end: end,
    generatedBy: generatedBy,
    activeFilters: activeFilters,
  );
  final tablas = [
    _buildTareas(excel, tasks: tasks, catalog: catalog),
    _buildClientes(excel, tasks: tasks, catalog: catalog),
    _buildUsuarios(excel, tasks: tasks, catalog: catalog),
  ];

  // `Excel.createExcel` seeds a blank "Sheet1"; it is only in the way.
  excel.delete('Sheet1');

  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('No se pudo generar el archivo de Excel.');
  }

  // Resumen is left as plain cells on purpose: it is a cover page of
  // label/value pairs, not a list, and a filter dropdown over "Periodo" and
  // "Generado por" would be noise.
  return deliverFile(
    mimeType: FileMime.xlsx,
    fileName:
        'reporte_checu_${AppDateUtils.formatDateKey(start)}_a_${AppDateUtils.formatDateKey(end)}.xlsx',
    bytes: addExcelTables(bytes, tablas),
  );
}

void _buildResumen(
  Excel excel, {
  required List<TaskModel> tasks,
  required CatalogProvider catalog,
  required DateTime start,
  required DateTime end,
  required String generatedBy,
  required List<String> activeFilters,
}) {
  final sheet = excel['Resumen'];
  final kpis = computeTaskKpis(tasks, catalog);

  void par(String label, String value) =>
      sheet.appendRow([TextCellValue(label), TextCellValue(value)]);

  sheet.merge(
    CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0),
    customValue: TextCellValue('Reporte de ${AppConstants.appName}'),
  );
  sheet
      .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
      .cellStyle = CellStyle(
    bold: true,
    fontSize: 16,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );
  sheet.appendRow([]);

  par(
    'Periodo',
    '${AppDateUtils.formatShortDate(start)} a ${AppDateUtils.formatShortDate(end)}',
  );
  par('Generado', AppDateUtils.formatDateTimeOrDash(DateTime.now()));
  par('Generado por', generatedBy);
  par(
    'Filtros aplicados',
    activeFilters.isEmpty
        ? 'Ninguno (todas las tareas del periodo)'
        : activeFilters.join(' · '),
  );
  sheet.appendRow([]);

  sheet.appendRow([TextCellValue('Indicadores')]);
  sheet
      .cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: sheet.maxRows - 1),
      )
      .cellStyle = CellStyle(
    bold: true,
  );

  sheet.appendRow([TextCellValue('Tareas'), IntCellValue(kpis.total)]);
  sheet.appendRow([TextCellValue('Completadas'), IntCellValue(kpis.completed)]);
  sheet.appendRow([TextCellValue('Pendientes'), IntCellValue(kpis.pending)]);
  sheet.appendRow([
    TextCellValue('Reprogramadas'),
    IntCellValue(kpis.rescheduled),
  ]);
  sheet.appendRow([TextCellValue('Canceladas'), IntCellValue(kpis.cancelled)]);
  sheet.appendRow([
    TextCellValue('Cumplimiento'),
    TextCellValue('${kpis.compliancePercent}%'),
  ]);
  sheet.appendRow([
    TextCellValue('Base del cumplimiento'),
    TextCellValue(
      '${kpis.completed} de ${kpis.countable} — las canceladas no cuentan '
      'como incumplimiento',
    ),
  ]);

  sheet.setColumnWidth(0, 24);
  sheet.setColumnWidth(1, 60);
}

TableSpec _buildTareas(
  Excel excel, {
  required List<TaskModel> tasks,
  required CatalogProvider catalog,
}) {
  final sheet = excel['Tareas'];
  const encabezados = [
    'Fecha',
    'Hora',
    'Cliente',
    'Teléfono',
    'Tipo',
    'Equipo',
    'Encargado',
    'Estado',
    'Reprogramaciones',
    'Creada',
    'Creada por',
    'Completada',
    'Último cambio por',
    'Observaciones',
  ];
  writeHeader(
    sheet,
    encabezados,
    widths: const [12, 8, 26, 16, 18, 16, 18, 14, 10, 18, 18, 18, 18, 40],
  );

  for (final t in tasks) {
    sheet.appendRow([
      TextCellValue(t.date),
      TextCellValue(t.hour),
      TextCellValue(t.clientName),
      TextCellValue(t.clientPhone),
      TextCellValue(catalog.taskTypeName(t.taskTypeId)),
      TextCellValue(catalog.groupName(t.groupId)),
      TextCellValue(catalog.userName(t.assignedUserId)),
      TextCellValue(catalog.statusName(t.statusId)),
      IntCellValue(t.rescheduledCount),
      TextCellValue(AppDateUtils.formatDateTimeOrDash(t.createdAt)),
      TextCellValue(t.createdBy == null ? '-' : catalog.userName(t.createdBy)),
      TextCellValue(AppDateUtils.formatDateTimeOrDash(t.completedAt)),
      TextCellValue(t.updatedBy == null ? '-' : catalog.userName(t.updatedBy)),
      TextCellValue(t.observations),
    ]);
  }

  return TableSpec(
    sheet: 'Tareas',
    headers: encabezados,
    dataRows: tasks.length,
  );
}

class _ClienteStats {
  _ClienteStats(this.nombre, this.telefono);

  final String nombre;
  final String telefono;
  int total = 0;
  int completadas = 0;
  int canceladas = 0;
  int reprogramaciones = 0;
  String? ultimaFecha;
}

TableSpec _buildClientes(
  Excel excel, {
  required List<TaskModel> tasks,
  required CatalogProvider catalog,
}) {
  final sheet = excel['Clientes'];
  final completedId = catalog.completedStatusId;
  final cancelledId = catalog.cancelledStatusId;

  final stats = <String, _ClienteStats>{};
  for (final t in tasks) {
    // Same key as mostAttendedClient: the real client record when there is
    // one, so correcting a name does not split somebody into two rows.
    final key = t.clientId ?? '${t.clientName}|${t.clientPhone}';
    final s = stats.putIfAbsent(
      key,
      () => _ClienteStats(t.clientName, t.clientPhone),
    );
    s.total++;
    if (t.statusId == completedId) s.completadas++;
    if (t.statusId == cancelledId) s.canceladas++;
    s.reprogramaciones += t.rescheduledCount;
    if (s.ultimaFecha == null || t.date.compareTo(s.ultimaFecha!) > 0) {
      s.ultimaFecha = t.date;
    }
  }

  const encabezados = [
    'Cliente',
    'Teléfono',
    'Tareas',
    'Completadas',
    'Canceladas',
    'Reprogramaciones',
    'Última tarea',
  ];
  writeHeader(sheet, encabezados, widths: const [30, 16, 10, 12, 12, 16, 14]);

  final ordenados = stats.values.toList()
    ..sort((a, b) => b.total.compareTo(a.total));

  for (final c in ordenados) {
    sheet.appendRow([
      TextCellValue(c.nombre),
      TextCellValue(c.telefono),
      IntCellValue(c.total),
      IntCellValue(c.completadas),
      IntCellValue(c.canceladas),
      IntCellValue(c.reprogramaciones),
      TextCellValue(c.ultimaFecha ?? '-'),
    ]);
  }

  return TableSpec(
    sheet: 'Clientes',
    headers: encabezados,
    dataRows: ordenados.length,
  );
}

TableSpec _buildUsuarios(
  Excel excel, {
  required List<TaskModel> tasks,
  required CatalogProvider catalog,
}) {
  final sheet = excel['Usuarios'];
  final completedId = catalog.completedStatusId;
  final cancelledId = catalog.cancelledStatusId;

  final asignadas = <String, int>{};
  final completadas = <String, int>{};
  final canceladas = <String, int>{};
  for (final t in tasks) {
    asignadas[t.assignedUserId] = (asignadas[t.assignedUserId] ?? 0) + 1;
    if (t.statusId == completedId) {
      completadas[t.assignedUserId] = (completadas[t.assignedUserId] ?? 0) + 1;
    }
    if (t.statusId == cancelledId) {
      canceladas[t.assignedUserId] = (canceladas[t.assignedUserId] ?? 0) + 1;
    }
  }

  const encabezados = [
    'Nombre',
    'Correo',
    'Rol',
    'Equipos',
    'Activo',
    'Asignadas',
    'Completadas',
    'Canceladas',
    'Cumplimiento',
    'Racha actual',
    'Racha máxima',
    'Último acceso',
  ];
  writeHeader(
    sheet,
    encabezados,
    widths: const [24, 28, 22, 24, 8, 10, 12, 12, 14, 12, 12, 18],
  );

  // Every user in the empresa, not only the ones who appear in the filtered
  // tasks: a person with zero rows is exactly the thing worth spotting, and
  // they would be invisible if the sheet were built from the tasks alone.
  final usuarios = List<AppUser>.from(catalog.users)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  for (final u in usuarios) {
    final total = asignadas[u.id] ?? 0;
    final hechas = completadas[u.id] ?? 0;
    final anuladas = canceladas[u.id] ?? 0;
    final base = total - anuladas;

    sheet.appendRow([
      TextCellValue(u.name),
      TextCellValue(u.email),
      TextCellValue(_rolLegible(u.role)),
      TextCellValue(catalog.groupNames(u.groupIds)),
      TextCellValue(u.isActive ? 'Sí' : 'No'),
      IntCellValue(total),
      IntCellValue(hechas),
      IntCellValue(anuladas),
      TextCellValue(base <= 0 ? '-' : '${(hechas * 100 / base).round()}%'),
      IntCellValue(u.streakDays),
      IntCellValue(u.maxStreakDays),
      TextCellValue(AppDateUtils.formatDateTimeOrDash(u.lastLogin)),
    ]);
  }

  return TableSpec(
    sheet: 'Usuarios',
    headers: encabezados,
    dataRows: usuarios.length,
  );
}

String _rolLegible(String role) => switch (role) {
  AppRoles.superAdmin => 'Administrador general',
  AppRoles.adminEquipo => 'Administrador de equipo',
  AppRoles.trabajadorNormal => 'Trabajador',
  _ => role,
};
