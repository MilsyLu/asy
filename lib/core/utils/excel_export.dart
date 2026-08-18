import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/download_bytes_web_stub.dart'
    if (dart.library.js_interop) '../../services/download_bytes_web.dart';

const _mimeXlsx =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Delivers a built workbook to the user: a plain browser download on web, the
/// native share sheet on mobile.
///
/// Web goes through `downloadBytes`, not share_plus, and that is not a style
/// choice — this project already learned it once, for the QR download. On
/// Windows, share_plus sees the Web Share API and opens the operating system's
/// "Compartir" dialog instead of downloading. From the user's side the button
/// simply does nothing: no file, no error, no explanation. The first version of
/// this export repeated the mistake.
Future<void> shareExcelBytes({
  required String fileName,
  required List<int> bytes,
}) async {
  if (kIsWeb) {
    downloadBytes(Uint8List.fromList(bytes), fileName, _mimeXlsx);
    return;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: fileName),
  );
}

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
