import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/download_bytes_web_stub.dart'
    if (dart.library.js_interop) '../../services/download_bytes_web.dart';

/// MIME types of everything CheCu hands to the user.
///
/// Kept together because the type travels with the bytes: the browser decides
/// what to do with a download from it, and a PDF delivered as a spreadsheet is
/// a file the machine opens with the wrong program.
abstract final class FileMime {
  static const csv = 'text/csv;charset=utf-8';
  static const xlsx =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const pdf = 'application/pdf';
}

/// Hands [bytes] to the user: a plain browser download on web, the native
/// share sheet on mobile.
///
/// The single place every export goes through, so the web/mobile split and the
/// choice below are made once. Web uses `downloadBytes` — an `<a download>`
/// click — and not share_plus, and that is not a preference: on Windows,
/// share_plus finds the Web Share API and opens the operating system's
/// "Compartir" dialog instead of downloading. The button then appears to do
/// nothing at all. This project learned that once with the QR download and
/// then repeated it with the first Excel export; having one function means
/// there is only one place left for it to happen again.
Future<void> deliverFile({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
}) async {
  if (kIsWeb) {
    downloadBytes(Uint8List.fromList(bytes), fileName, mimeType);
    return;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: fileName),
  );
}
