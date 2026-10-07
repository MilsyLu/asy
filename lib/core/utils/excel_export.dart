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

/// Los bytes del libro, sin efectos secundarios.
///
/// Siempre `encode()`, nunca `save()`. En web, `Excel.save()` no se limita a
/// devolver los bytes: además dispara por su cuenta una descarga del navegador
/// llamada "FlutterExcel.xlsx". Quien después entrega el archivo con su nombre
/// real termina bajando dos: el bueno y uno anónimo del mismo peso.
///
/// Esta función existe para que esa trampa tenga un solo sitio donde evitarse,
/// igual que `deliverFile` con la descarga en web. Pasó una vez con el
/// descargador de VinApp después de que Reportes ya lo hiciera bien.
List<int> excelBytes(Excel excel) {
  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('No se pudo generar el archivo de Excel.');
  }
  return bytes;
}
