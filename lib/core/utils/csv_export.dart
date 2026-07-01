import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
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
  final csv = const ListToCsvConverter().convert(rows);

  if (kIsWeb) {
    final bytes = const Utf8Encoder().convert(csv);
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: fileName, mimeType: 'text/csv;charset=utf-8')],
      text: fileName,
    );
    return;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(csv);
  await Share.shareXFiles([XFile(file.path)], text: fileName);
}
