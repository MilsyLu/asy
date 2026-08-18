import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/app_constants.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/file_delivery.dart';
import '../../core/utils/report_metrics.dart';
import '../../models/task_model.dart';
import '../../providers/catalog_provider.dart';

/// The printable version of the report.
///
/// Deliberately not the spreadsheet with a different extension. Excel is for
/// working the data — filtering, summing, pivoting. This is the one you send
/// to somebody or file away: it opens the same on any machine, cannot be
/// edited by accident, and reads as a document rather than a grid.
///
/// So it carries what a reader needs and the spreadsheet does not bother with:
/// the period and the filters stated up front, the indicators as headlines,
/// compliance per team, and only the task columns that survive being printed.
/// The remaining detail — creation and completion timestamps, observations —
/// stays in the workbook, where there is room for it.
Future<void> exportReportPdf({
  required List<TaskModel> tasks,
  required CatalogProvider catalog,
  required DateTime start,
  required DateTime end,
  required String generatedBy,
  required List<String> activeFilters,
}) async {
  final kpis = computeTaskKpis(tasks, catalog);
  final grupos = computeGroupCompliance(tasks, catalog)
    ..sort((a, b) => b.percent.compareTo(a.percent));

  final theme = await _tema();
  final doc = pw.Document(
    title: 'Reporte de ${AppConstants.appName}',
    author: AppConstants.appDeveloper,
    theme: theme,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : _encabezadoCorrido(start, end),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}  ·  '
          '${AppConstants.appName} · ${AppConstants.appDeveloper}',
          style: pw.TextStyle(fontSize: 8, color: _gris),
        ),
      ),
      build: (context) => [
        _portada(start, end, generatedBy, activeFilters),
        pw.SizedBox(height: 18),
        _indicadores(kpis),
        pw.SizedBox(height: 18),
        if (grupos.isNotEmpty) ...[
          _titulo('Cumplimiento por equipo'),
          pw.SizedBox(height: 8),
          _tablaEquipos(grupos, catalog),
          pw.SizedBox(height: 18),
        ],
        _titulo('Detalle de tareas (${tasks.length})'),
        pw.SizedBox(height: 8),
        _tablaTareas(tasks, catalog),
      ],
    ),
  );

  await deliverFile(
    mimeType: FileMime.pdf,
    fileName:
        'reporte_checu_${AppDateUtils.formatDateKey(start)}_a_${AppDateUtils.formatDateKey(end)}.pdf',
    bytes: await doc.save(),
  );
}

const _navy = PdfColor.fromInt(0xFF1A234A);
const _gris = PdfColor.fromInt(0xFF6B7280);
const _lineas = PdfColor.fromInt(0xFFE4E1D9);
const _crema = PdfColor.fromInt(0xFFF5F1E8);

/// Embeds the app's own typeface instead of leaning on the PDF standard fonts.
///
/// Two reasons, and the second is the one that matters: the document then looks
/// like the product it came from, and the built-in fonts only carry Latin-1 —
/// anything outside it renders as a blank box. This report is full of Spanish
/// names, and a client called "Panadería" losing its í in the file you send out
/// is not a detail.
Future<pw.ThemeData> _tema() async {
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/PlusJakartaSans-400.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/PlusJakartaSans-700.ttf'),
  );
  return pw.ThemeData.withFont(base: regular, bold: bold);
}

pw.Widget _titulo(String texto) => pw.Text(
  texto,
  style: pw.TextStyle(
    fontSize: 13,
    fontWeight: pw.FontWeight.bold,
    color: _navy,
  ),
);

pw.Widget _encabezadoCorrido(DateTime start, DateTime end) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 12),
  padding: const pw.EdgeInsets.only(bottom: 6),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _lineas)),
  ),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'Reporte de ${AppConstants.appName}',
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: _navy,
        ),
      ),
      pw.Text(
        '${AppDateUtils.formatShortDate(start)} — ${AppDateUtils.formatShortDate(end)}',
        style: pw.TextStyle(fontSize: 9, color: _gris),
      ),
    ],
  ),
);

pw.Widget _portada(
  DateTime start,
  DateTime end,
  String generatedBy,
  List<String> activeFilters,
) {
  pw.Widget dato(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 92,
          child: pw.Text(label, style: pw.TextStyle(fontSize: 9, color: _gris)),
        ),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    ),
  );

  return pw.Container(
    padding: const pw.EdgeInsets.all(18),
    decoration: pw.BoxDecoration(
      color: _crema,
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Reporte de ${AppConstants.appName}',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: _navy,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          AppConstants.appTagline,
          style: pw.TextStyle(fontSize: 9, color: _gris),
        ),
        pw.SizedBox(height: 14),
        dato(
          'Periodo',
          '${AppDateUtils.formatShortDate(start)} a ${AppDateUtils.formatShortDate(end)}',
        ),
        dato('Generado', AppDateUtils.formatDateTimeOrDash(DateTime.now())),
        dato('Generado por', generatedBy),
        // Printed on the first page on purpose. A PDF is the copy that gets
        // forwarded and filed, and months later there is nothing else on it to
        // say whether these numbers were the whole period or one team's slice.
        dato(
          'Filtros',
          activeFilters.isEmpty
              ? 'Ninguno (todas las tareas del periodo)'
              : activeFilters.join('  ·  '),
        ),
      ],
    ),
  );
}

pw.Widget _indicadores(TaskKpis kpis) {
  pw.Widget tarjeta(String label, String value, {bool destacada = false}) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: pw.BoxDecoration(
            color: destacada ? _navy : PdfColors.white,
            border: pw.Border.all(color: destacada ? _navy : _lineas),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: destacada ? PdfColors.white : _gris,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: destacada ? PdfColors.white : _navy,
                ),
              ),
            ],
          ),
        ),
      );

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        children: [
          tarjeta('Tareas', '${kpis.total}'),
          tarjeta('Completadas', '${kpis.completed}'),
          tarjeta('Pendientes', '${kpis.pending}'),
          tarjeta('Reprogramadas', '${kpis.rescheduled}'),
          tarjeta('Canceladas', '${kpis.cancelled}'),
          tarjeta(
            'Cumplimiento',
            '${kpis.compliancePercent}%',
            destacada: true,
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Cumplimiento = ${kpis.completed} completadas de ${kpis.countable} '
        'que se podían hacer. Las canceladas no cuentan como incumplimiento.',
        style: pw.TextStyle(fontSize: 7.5, color: _gris),
      ),
    ],
  );
}

pw.Widget _tablaEquipos(List<GroupCompliance> grupos, CatalogProvider catalog) {
  return pw.TableHelper.fromTextArray(
    headers: const [
      'Equipo',
      'Asignadas',
      'Completadas',
      'Canceladas',
      'Cumplimiento',
    ],
    data: [
      for (final g in grupos)
        [
          catalog.groupName(g.groupId),
          '${g.assigned}',
          '${g.completed}',
          '${g.cancelled}',
          '${g.percent}%',
        ],
    ],
    headerStyle: pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    headerDecoration: const pw.BoxDecoration(color: _navy),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellHeight: 16,
    oddRowDecoration: const pw.BoxDecoration(color: _crema),
    headerAlignment: pw.Alignment.centerLeft,
    cellAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerRight,
      2: pw.Alignment.centerRight,
      3: pw.Alignment.centerRight,
      4: pw.Alignment.centerRight,
    },
    border: pw.TableBorder.all(color: _lineas, width: 0.5),
  );
}

pw.Widget _tablaTareas(List<TaskModel> tasks, CatalogProvider catalog) {
  if (tasks.isEmpty) {
    return pw.Text(
      'No hay tareas en el periodo seleccionado.',
      style: pw.TextStyle(fontSize: 9, color: _gris),
    );
  }

  return pw.TableHelper.fromTextArray(
    // Eight columns is what fits on A4 portrait and stays readable printed.
    // The rest of the detail lives in the workbook, which has the room.
    headers: const [
      'Fecha',
      'Hora',
      'Cliente',
      'Teléfono',
      'Tipo',
      'Equipo',
      'Encargado',
      'Estado',
    ],
    data: [
      for (final t in tasks)
        [
          t.date,
          t.hour,
          t.clientName,
          t.clientPhone,
          catalog.taskTypeName(t.taskTypeId),
          catalog.groupName(t.groupId),
          catalog.userName(t.assignedUserId),
          catalog.statusName(t.statusId),
        ],
    ],
    headerStyle: pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    headerDecoration: const pw.BoxDecoration(color: _navy),
    cellStyle: const pw.TextStyle(fontSize: 7.5),
    cellHeight: 15,
    oddRowDecoration: const pw.BoxDecoration(color: _crema),
    headerAlignment: pw.Alignment.centerLeft,
    cellAlignment: pw.Alignment.centerLeft,
    border: pw.TableBorder.all(color: _lineas, width: 0.5),
    columnWidths: const {
      0: pw.FixedColumnWidth(48),
      1: pw.FixedColumnWidth(30),
      2: pw.FlexColumnWidth(2.2),
      3: pw.FixedColumnWidth(56),
      4: pw.FlexColumnWidth(1.4),
      5: pw.FlexColumnWidth(1.1),
      6: pw.FlexColumnWidth(1.2),
      7: pw.FlexColumnWidth(1.1),
    },
  );
}
