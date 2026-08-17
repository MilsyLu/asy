import 'dart:convert';
import 'dart:io';

// Aliased: csv 8 exports a top-level instance also called `csv`, which the
// local variable below would otherwise shadow.
import 'package:csv/csv.dart' as csv_lib;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Converts [rows] to CSV and delivers it to the user:
/// - Web: encodes to UTF-8 bytes and triggers a browser download via
///   share_plus (no filesystem access required).
/// - Mobile: writes to a temporary file and opens the native share sheet.
Future<void> exportAndShareCsv({
  required String fileName,
  required List<List<dynamic>> rows,
}) async {
  final csv = csv_lib.csv.encode(rows);

  if (kIsWeb) {
    final bytes = const Utf8Encoder().convert(csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, name: fileName, mimeType: 'text/csv;charset=utf-8'),
        ],
        // XFile.fromData carries no filename on its own, so the browser would
        // otherwise save the export under a generated name.
        fileNameOverrides: [fileName],
        text: fileName,
      ),
    );
    return;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(csv);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: fileName),
  );
}
