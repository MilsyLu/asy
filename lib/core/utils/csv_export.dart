import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Converts [rows] to CSV, writes it to a temporary [fileName] and opens
/// the native share sheet so the user can save or send the file.
Future<void> exportAndShareCsv({
  required String fileName,
  required List<List<dynamic>> rows,
}) async {
  final csv = const ListToCsvConverter().convert(rows);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(csv);
  await Share.shareXFiles([XFile(file.path)], text: fileName);
}
