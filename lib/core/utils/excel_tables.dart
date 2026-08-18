import 'dart:convert';

import 'package:archive/archive.dart';

/// One sheet that should arrive already formatted as an Excel table.
class TableSpec {
  const TableSpec({
    required this.sheet,
    required this.headers,
    required this.dataRows,
  });

  /// Sheet name, as passed to `excel['...']`.
  final String sheet;

  /// Header texts of row 1, in order. Excel requires these to match the cells
  /// exactly, be unique and be non-empty.
  final List<String> headers;

  /// Rows below the header. Zero is valid — an empty table still filters.
  final int dataRows;
}

/// Rewrites an `.xlsx` so the given sheets open as real Excel tables: filter
/// dropdowns on every column, banded rows, and a header that stays put while
/// you scroll.
///
/// The `excel` package has no API for this — no tables, no autofilter — so the
/// parts are written into the package by hand. That is a deliberate trade: the
/// alternative was leaving Michel to press Ctrl+T on three sheets after every
/// export, which is exactly the step he asked to be rid of.
///
/// A table is four coordinated edits, and Excel refuses the file outright if
/// any one of them is off, so each is done from what the package actually
/// produced rather than from assumption:
///   1. `xl/tables/tableN.xml` — the definition.
///   2. a relationship from the sheet to that part.
///   3. `<tableParts>` at the end of the sheet, referencing the relationship.
///   4. a content-type override, without which the part is invisible.
/// Every part is read and written as UTF-8, deliberately.
///
/// The first version used `String.fromCharCodes` and `.codeUnits`, which are
/// UTF-16 units, not bytes: the "é" of "Teléfono" went in as the single byte
/// 0xE9 instead of the two UTF-8 bytes it needs, leaving `table1.xml`
/// malformed. Excel refused the whole workbook and offered to repair it. The
/// tests missed it because every header they used was pure ASCII — the report
/// itself has "Teléfono", "Última tarea" and "Racha máxima".
List<int> addExcelTables(List<int> xlsxBytes, List<TableSpec> specs) {
  final archive = ZipDecoder().decodeBytes(xlsxBytes);
  final files = <String, List<int>>{
    for (final f in archive.files)
      if (f.isFile) f.name: f.content as List<int>,
  };

  final workbook = utf8.decode(files['xl/workbook.xml']!);
  final workbookRels = utf8.decode(files['xl/_rels/workbook.xml.rels']!);

  var tableIndex = 0;
  final contentTypeOverrides = <String>[];

  for (final spec in specs) {
    if (spec.headers.isEmpty) continue;

    final target = _sheetTarget(workbook, workbookRels, spec.sheet);
    if (target == null) continue;

    tableIndex++;
    final tablePath = 'xl/tables/table$tableIndex.xml';
    final sheetPath = 'xl/$target';
    final relsPath = _relsPathFor(sheetPath);

    // Header row plus data. A table always covers row 1.
    final lastColumn = _columnLetter(spec.headers.length - 1);
    final ref = 'A1:$lastColumn${spec.dataRows + 1}';

    files[tablePath] = utf8.encode(
      _tableXml(
        id: tableIndex,
        name: _tableName(spec.sheet, tableIndex),
        ref: ref,
        headers: spec.headers,
      ),
    );

    final relId = _appendRelationship(files, relsPath, tablePath);
    files[sheetPath] = utf8.encode(
      _withTableParts(utf8.decode(files[sheetPath]!), relId),
    );

    contentTypeOverrides.add(
      '<Override PartName="/$tablePath" ContentType="application/vnd.'
      'openxmlformats-officedocument.spreadsheetml.table+xml"/>',
    );
  }

  if (contentTypeOverrides.isEmpty) return xlsxBytes;

  files['[Content_Types].xml'] = utf8.encode(
    utf8
        .decode(files['[Content_Types].xml']!)
        .replaceFirst('</Types>', '${contentTypeOverrides.join()}</Types>'),
  );

  final out = Archive();
  files.forEach((name, content) {
    out.addFile(ArchiveFile(name, content.length, content));
  });
  return ZipEncoder().encode(out)!;
}

/// `worksheets/sheet2.xml` for a sheet name, resolved through the workbook's
/// own relationships. Sheet order and file numbering do not always agree, so
/// guessing from position would eventually attach a table to the wrong sheet.
String? _sheetTarget(String workbook, String rels, String sheetName) {
  final sheetTag = RegExp(
    '<sheet[^>]*name="${RegExp.escape(sheetName)}"[^>]*/>',
  ).firstMatch(workbook);
  if (sheetTag == null) return null;

  final relId = RegExp(
    'r:id="([^"]+)"',
  ).firstMatch(sheetTag.group(0)!)?.group(1);
  if (relId == null) return null;

  final rel = RegExp(
    '<Relationship[^>]*Id="${RegExp.escape(relId)}"[^>]*/>',
  ).firstMatch(rels);
  if (rel == null) return null;

  return RegExp('Target="([^"]+)"').firstMatch(rel.group(0)!)?.group(1);
}

String _relsPathFor(String sheetPath) {
  final parts = sheetPath.split('/');
  final file = parts.removeLast();
  return '${parts.join('/')}/_rels/$file.rels';
}

/// Adds a table relationship, creating the sheet's rels part when it has none
/// — only the first sheet gets one from the package.
String _appendRelationship(
  Map<String, List<int>> files,
  String relsPath,
  String tablePath,
) {
  const type =
      'http://schemas.openxmlformats.org/officeDocument/2006/'
      'relationships/table';
  final target = '../${tablePath.split('/').skip(1).join('/')}';

  final existing = files[relsPath];
  if (existing == null) {
    const relId = 'rId1';
    files[relsPath] = utf8.encode(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/'
      'package/2006/relationships">'
      '<Relationship Id="$relId" Type="$type" Target="$target"/>'
      '</Relationships>',
    );
    return relId;
  }

  final xml = utf8.decode(existing);
  // Continue the file's own numbering instead of assuming: sheet 1 already
  // carries a drawing relationship, and reusing its id would break both.
  final used = RegExp('Id="rId(\\d+)"')
      .allMatches(xml)
      .map((m) => int.parse(m.group(1)!))
      .fold<int>(0, (max, v) => v > max ? v : max);
  final relId = 'rId${used + 1}';

  files[relsPath] = utf8.encode(
    xml.replaceFirst(
      '</Relationships>',
      '<Relationship Id="$relId" Type="$type" Target="$target"/>'
          '</Relationships>',
    ),
  );
  return relId;
}

/// `<tableParts>` belongs at the very end of the worksheet, after
/// `<pageMargins>`. Excel validates child order and rejects the file if it
/// appears earlier.
String _withTableParts(String sheetXml, String relId) {
  return sheetXml.replaceFirst(
    '</worksheet>',
    '<tableParts count="1"><tablePart r:id="$relId"/></tableParts>'
        '</worksheet>',
  );
}

String _tableXml({
  required int id,
  required String name,
  required String ref,
  required List<String> headers,
}) {
  final columns = [
    for (var i = 0; i < headers.length; i++)
      '<tableColumn id="${i + 1}" name="${_escape(headers[i])}"/>',
  ].join();

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<table xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'id="$id" name="$name" displayName="$name" ref="$ref" totalsRowShown="0">'
      '<autoFilter ref="$ref"/>'
      '<tableColumns count="${headers.length}">$columns</tableColumns>'
      '<tableStyleInfo name="TableStyleMedium2" showFirstColumn="0" '
      'showLastColumn="0" showRowStripes="1" showColumnStripes="0"/>'
      '</table>';
}

/// A table's name is a defined name in the workbook: letters, digits and
/// underscores only, and it cannot start with a digit.
String _tableName(String sheet, int index) {
  final clean = sheet.replaceAll(RegExp('[^A-Za-z0-9_]'), '');
  if (clean.isEmpty) return 'Tabla$index';
  return RegExp('^[0-9]').hasMatch(clean) ? 'T$clean' : clean;
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// 0 → A, 25 → Z, 26 → AA.
String _columnLetter(int index) {
  var i = index;
  final buffer = StringBuffer();
  while (i >= 0) {
    buffer.write(String.fromCharCode(65 + (i % 26)));
    i = (i ~/ 26) - 1;
  }
  return utf8.decode(buffer.toString().codeUnits.reversed.toList());
}
