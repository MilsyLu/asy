import 'package:excel/excel.dart';

/// Header style shared by every sheet: white on brand navy, so the first row
/// reads as a header even once the file leaves CheCu.
CellStyle get headerStyle => CellStyle(
  bold: true,
  fontColorHex: ExcelColor.white,
  backgroundColorHex: ExcelColor.fromHexString('#1A234A'),
  horizontalAlign: HorizontalAlign.Left,
);

/// Writes [headers] as row 1 with [headerStyle] and sets column widths.
///
/// Not frozen: `excel` 4.0.6 has no API for freeze panes, so the header
/// scrolls away on a long list like it would in any CSV. Whoever needs it
/// pinned can do it in Excel with one click; writing the XML by hand to avoid
/// that is not worth the fragility.
void writeHeader(Sheet sheet, List<String> headers, {List<double>? widths}) {
  sheet.appendRow([for (final h in headers) TextCellValue(h)]);
  for (var i = 0; i < headers.length; i++) {
    sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .cellStyle =
        headerStyle;
    sheet.setColumnWidth(
      i,
      widths != null && i < widths.length ? widths[i] : 18,
    );
  }
}
