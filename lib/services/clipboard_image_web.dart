// Web-only implementation — compiled exclusively when dart:js_interop is
// available (i.e. Flutter web builds). Never compiled by Android / iOS.
//
// Lets the VinApp Print image picker accept a pasted screenshot (Ctrl+V,
// e.g. after Win+Shift+S) in addition to picking a saved file — a common
// workflow for a settings screen that has to be captured in pieces (see
// PrinterConfigImagePicker).

import 'dart:js_interop';
import 'dart:typed_data';

@JS('window.addEventListener')
external void _addEventListener(String type, JSFunction listener);

@JS('window.removeEventListener')
external void _removeEventListener(String type, JSFunction listener);

extension type _ClipboardEvent._(JSObject _) implements JSObject {
  external _DataTransfer? get clipboardData;
}

extension type _DataTransfer._(JSObject _) implements JSObject {
  external _DataTransferItemList get items;
}

extension type _DataTransferItemList._(JSObject _) implements JSObject {
  external int get length;
  external _DataTransferItem item(int index);
}

extension type _DataTransferItem._(JSObject _) implements JSObject {
  external String get kind;
  external String get type;
  external JSObject? getAsFile();
}

extension type _Blob._(JSObject _) implements JSObject {
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

typedef ClipboardImageCallback = void Function(Uint8List bytes, String mediaType);

JSFunction? _currentListener;

/// Starts listening for paste events anywhere in the page; any image found
/// in the pasted clipboard data is decoded and handed to [onImage]. Replaces
/// any previously registered listener — only one is ever active.
void registerClipboardImageListener(ClipboardImageCallback onImage) {
  unregisterClipboardImageListener();
  final listener = ((JSAny event) {
    _handlePaste(event, onImage);
  }).toJS;
  _currentListener = listener;
  _addEventListener('paste', listener);
}

void unregisterClipboardImageListener() {
  final listener = _currentListener;
  if (listener != null) {
    _removeEventListener('paste', listener);
    _currentListener = null;
  }
}

void _handlePaste(JSAny eventAny, ClipboardImageCallback onImage) async {
  final event = eventAny as _ClipboardEvent;
  final data = event.clipboardData;
  if (data == null) return;
  final items = data.items;
  for (var i = 0; i < items.length; i++) {
    final item = items.item(i);
    if (item.kind != 'file' || !item.type.startsWith('image/')) continue;
    final fileObj = item.getAsFile();
    if (fileObj == null) continue;
    final blob = fileObj as _Blob;
    final buffer = await blob.arrayBuffer().toDart;
    onImage(buffer.toDart.asUint8List(), item.type);
  }
}
