// Stub — compiled on Android / iOS / desktop where dart:js_interop is
// unavailable. Every call-site is already inside an `if (kIsWeb)` guard, so
// these bodies are never reached at runtime.

import 'dart:typed_data';

typedef ClipboardImageCallback = void Function(Uint8List bytes, String mediaType);

void registerClipboardImageListener(ClipboardImageCallback onImage) {}

void unregisterClipboardImageListener() {}
