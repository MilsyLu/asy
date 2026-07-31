// Web-only implementation — compiled exclusively when dart:js_interop is
// available (Flutter web builds). Never compiled on Android / iOS.
//
// Triggers a real browser download (straight to Descargas) via a data URL
// + throwaway <a download> click — deliberately NOT using share_plus here,
// since on Windows/Edge `Share.shareXFiles` invokes the native OS
// "Compartir" dialog instead of a plain download when the Web Share API
// with files is available, which isn't what "Descargar imagen" should do.

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('document.createElement')
external JSObject _createElement(String tag);

extension type _AnchorElement._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  final base64Data = base64Encode(bytes);
  final anchor = _createElement('a') as _AnchorElement;
  anchor.href = 'data:$mimeType;base64,$base64Data';
  anchor.download = filename;
  anchor.click();
}
