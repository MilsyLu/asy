import 'dart:convert';
import 'dart:io';

// Aliased: csv 8 exports a top-level instance also called `csv`, which the
// local variable below would otherwise shadow.
import 'package:csv/csv.dart' as csv_lib;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/download_bytes_web_stub.dart'
    if (dart.library.js_interop) '../../services/download_bytes_web.dart';

/// Converts [rows] to CSV and delivers it to the user: a plain browser
/// download on web, the native share sheet on mobile.
///
/// Web goes through `downloadBytes` rather than share_plus, for the reason
/// spelled out in `download_bytes_web.dart`: on Windows, share_plus sees the
/// Web Share API and opens the operating system's "Compartir" dialog instead
/// of downloading, so the button appears to do nothing. This path had the same
/// latent problem before anyone tried it there.
///
/// Two details make the file open correctly in Spanish Excel, which is where
/// it is going:
///  - fields separated by `;`, because that is the list separator Excel
///    expects in that locale — with commas every row lands in column A;
///  - a UTF-8 byte-order mark, without which Excel renders "Teléfono" as
///    "TelÃ©fono".
///
/// Both come from the `csv` package's own Excel profile rather than from
/// settings written out here.
Future<void> exportAndShareCsv({
  required String fileName,
  required List<List<dynamic>> rows,
}) async {
  // `csv_lib.excel` instead of `csv_lib.csv`: the package ships a profile for
  // exactly this, with `fieldDelimiter: ';'` and `addBom: true` already set.
  // Hand-rolling both was reinventing what was one identifier away.
  final csv = csv_lib.excel.encode(rows);
  final bytes = Uint8List.fromList(const Utf8Encoder().convert(csv));

  if (kIsWeb) {
    downloadBytes(bytes, fileName, 'text/csv;charset=utf-8');
    return;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: fileName),
  );
}
