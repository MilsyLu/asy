import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../services/download_bytes_web_stub.dart'
    if (dart.library.js_interop) '../../services/download_bytes_web.dart';

/// Generic "paste a link, get a QR" utility — open to any signed-in user
/// (no permission gate), lives as its own top-level sidebar item. Ports the
/// standalone `generadorqr.html` tool Michel shared into a real CheCu
/// screen: same fields (nombre del archivo, enlace, tamaño) and same
/// download-as-PNG behavior, using `qr_flutter` to render/rasterize instead
/// of a CDN-loaded JS library.
class QrGeneratorPage extends StatefulWidget {
  const QrGeneratorPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<QrGeneratorPage> createState() => _QrGeneratorPageState();
}

class _QrSizeOption {
  const _QrSizeOption(this.label, this.value);
  final String label;
  final double value;
}

const _sizeOptions = [
  _QrSizeOption('Pequeño', 150),
  _QrSizeOption('Mediano', 250),
  _QrSizeOption('Grande', 400),
];

class _QrGeneratorPageState extends State<QrGeneratorPage> {
  final _nameController = TextEditingController();
  final _linkController = TextEditingController();
  double _size = 250;
  String? _generatedText;
  bool _isSharing = false;

  @override
  void dispose() {
    _nameController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _generate() {
    final text = _linkController.text.trim();
    if (text.isEmpty) {
      SnackbarUtils.showError(context, 'Escribe un enlace primero.');
      return;
    }
    setState(() => _generatedText = text);
  }

  String _fileName() {
    final raw = _nameController.text.trim();
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), '-');
    return '${cleaned.isEmpty ? 'codigo-qr' : cleaned}.png';
  }

  Future<void> _download() async {
    final text = _generatedText;
    if (text == null || _isSharing) return;
    setState(() => _isSharing = true);
    try {
      final painter = QrPainter(
        data: text,
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
        dataModuleStyle:
            const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
      );
      // QrPainter only draws the black modules — it never fills a
      // background, so exporting via its own toImageData() gives a
      // transparent PNG (looks broken/invisible on a dark viewer). Paint a
      // white rect first so the downloaded file is actually white+black.
      final exportSize = _size * 2; // 2x the on-screen size for a sharper PNG.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, exportSize, exportSize),
        Paint()..color = Colors.white,
      );
      painter.paint(canvas, Size(exportSize, exportSize));
      final image =
          await recorder.endRecording().toImage(exportSize.toInt(), exportSize.toInt());
      final imageData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (imageData == null) throw Exception('empty image data');
      final bytes = imageData.buffer.asUint8List();
      final fileName = _fileName();
      if (kIsWeb) {
        // Direct browser download straight to Descargas — Share.shareXFiles
        // on web opens the OS's native "Compartir" dialog when the Web
        // Share API with files is available (e.g. Windows/Edge), which
        // isn't what a "Descargar imagen" button should do.
        downloadBytes(bytes, fileName, 'image/png');
      } else {
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: fileName, mimeType: 'image/png')],
          text: fileName,
        );
      }
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'No se pudo descargar el código QR.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final body = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidthNarrow),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.qrCode, color: colors.primary, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Generador de Códigos QR',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Pega un enlace, elige el tamaño y genera tu QR.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Nombre del archivo',
                    hintText: 'mi-codigo-qr',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _linkController,
                  style: TextStyle(color: colors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Enlace (URL)',
                    hintText: 'https://ejemplo.com',
                  ),
                  onSubmitted: (_) => _generate(),
                ),
                const SizedBox(height: 16),
                Text('Tamaño', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                SegmentedButton<double>(
                  segments: [
                    for (final opt in _sizeOptions)
                      ButtonSegment(value: opt.value, label: Text(opt.label)),
                  ],
                  selected: {_size},
                  onSelectionChanged: (s) => setState(() => _size = s.first),
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _generate,
                  child: const Text('Generar QR'),
                ),
                if (_generatedText != null) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: QrImageView(
                        data: _generatedText!,
                        size: _size,
                        backgroundColor: Colors.white,
                        gapless: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton.icon(
                      onPressed: _isSharing ? null : _download,
                      icon: _isSharing
                          ? const SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.download, size: 16),
                      label: const Text('Descargar imagen'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Generador de QR')),
      body: body,
    );
  }
}
