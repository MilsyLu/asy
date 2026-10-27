import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../widgets/confirm_dialog.dart';
import '../../services/download_bytes_web_stub.dart'
    if (dart.library.js_interop) '../../services/download_bytes_web.dart';

/// Generic "paste a link, get a QR" utility — open to any signed-in user
/// (no permission gate), lives as its own top-level sidebar item. Ports the
/// standalone `generadorqr.html` tool Michel shared into a real CheCu
/// screen: same fields (nombre del archivo, enlace, tamaño) and same
/// download-as-PNG behavior, using `qr_flutter` to render/rasterize instead
/// of a CDN-loaded JS library.
///
/// A Vinny menu link (`vinny.vinapp.co/?company=…`) can instead become a
/// "carta digital": the `generarCartaDigital` Cloud Function reads the menu
/// once and publishes a view-only page at `/carta/<company>`, and the QR
/// points there. Prices stay as they were at generation time; regenerating
/// keeps the same link, so a printed QR keeps working.
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

  bool _makeCarta = true;

  /// "domicilio" (lo que muestra Vinny) o "mesa" (lo que ve el mesero en
  /// VinApp). Son dos cartas distintas, cada una con su enlace y su QR.
  String _precios = 'domicilio';
  bool _isBuildingCarta = false;
  _CartaResult? _carta;

  /// Cartas already created by this empresa; null while the first load runs.
  List<_CartaListItem>? _cartas;
  String? _deletingSlug;
  String? _refreshingSlug;

  static final _vinnyLink = RegExp(
    r'^https?://(www\.)?vinny\.(vinapp\.co|la)/?\S*[?&]company=[A-Za-z0-9_-]+',
    caseSensitive: false,
  );

  bool get _isVinnyLink => _vinnyLink.hasMatch(_linkController.text.trim());
  bool get _willMakeCarta => _isVinnyLink && _makeCarta;

  @override
  void initState() {
    super.initState();
    // Rebuild so the "Crear carta digital" option appears as soon as a Vinny
    // link is pasted, not only after pressing Generar.
    _linkController.addListener(() => setState(() {}));
    _loadCartas();
  }

  Future<void> _loadCartas() async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('listarCartasDigitales')
          .call<Map<String, dynamic>>();
      final raw = (result.data['cartas'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _cartas = raw
            .map((e) => _CartaListItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      });
    } catch (_) {
      // The list is a convenience next to the generator; if it fails to load,
      // the generator itself still works, so stay quiet and show nothing.
      if (mounted) setState(() => _cartas = const []);
    }
  }

  Future<void> _deleteCarta(_CartaListItem item) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Borrar carta',
      message: '¿Borrar la carta de ${item.displayName}? Su enlace y el QR que '
          'ya se imprimió dejarán de mostrar la carta. Puedes volver a crearla '
          'cuando quieras con el mismo enlace de Vinny.',
      confirmLabel: 'Borrar',
      destructive: true,
    );
    if (!confirm || !mounted) return;
    setState(() => _deletingSlug = item.slug);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('borrarCartaDigital')
          .call<Map<String, dynamic>>({'slug': item.slug});
      if (!mounted) return;
      setState(() {
        _cartas = _cartas?.where((c) => c.slug != item.slug).toList();
        if (_carta?.slug == item.slug) {
          _carta = null;
          _generatedText = null;
        }
      });
      SnackbarUtils.showSuccess(context, 'Carta de ${item.displayName} borrada.');
    } on FirebaseFunctionsException catch (e) {
      if (mounted) SnackbarUtils.showError(context, e.message ?? 'No se pudo borrar la carta.');
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'No se pudo borrar la carta.');
    } finally {
      if (mounted) setState(() => _deletingSlug = null);
    }
  }

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
    if (_willMakeCarta) {
      _buildCarta(text);
      return;
    }
    setState(() {
      _generatedText = text;
      _carta = null;
    });
  }

  Future<void> _buildCarta(String vinnyUrl) async {
    if (_isBuildingCarta) return;
    setState(() => _isBuildingCarta = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'generarCartaDigital',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
          )
          .call<Map<String, dynamic>>({'url': vinnyUrl, 'precios': _precios});
      final carta = _CartaResult.fromMap(Map<String, dynamic>.from(result.data));
      if (!mounted) return;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = 'qr-carta-${carta.slug}';
      }
      setState(() {
        _carta = carta;
        _generatedText = carta.url;
      });
      _loadCartas();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, e.message ?? 'No se pudo crear la carta.');
      }
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'No se pudo crear la carta.');
    } finally {
      if (mounted) setState(() => _isBuildingCarta = false);
    }
  }

  Future<void> _openUrl(String url) async {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) SnackbarUtils.showError(context, 'No se pudo abrir la carta.');
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) SnackbarUtils.showSuccess(context, 'Enlace copiado.');
  }

  /// Vuelve a leer el menú en Vinny con el enlace guardado de la carta: los
  /// precios se ponen al día y el enlace (y el QR impreso) siguen iguales.
  Future<void> _refreshCarta(_CartaListItem item) async {
    if (_refreshingSlug != null) return;
    setState(() => _refreshingSlug = item.slug);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable(
            'generarCartaDigital',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 5)),
          )
          .call<Map<String, dynamic>>({'url': item.vinnyUrl, 'precios': item.precios});
      final carta = _CartaResult.fromMap(Map<String, dynamic>.from(result.data));
      await _loadCartas();
      if (mounted) {
        SnackbarUtils.showSuccess(
          context,
          'Carta de ${carta.displayName} actualizada: ${carta.productos} productos.',
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context, e.message ?? 'No se pudo actualizar la carta.');
      }
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'No se pudo actualizar la carta.');
    } finally {
      if (mounted) setState(() => _refreshingSlug = null);
    }
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
      await _saveQrPng(text, _fileName(), _size);
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'No se pudo descargar el código QR.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  /// "Descargar QR" de una tarjeta: tamaño Grande, que es el que sirve para
  /// imprimir en la mesa, y nombre de archivo por restaurante.
  Future<void> _downloadCartaQr(_CartaListItem item) async {
    try {
      await _saveQrPng(item.url, 'qr-carta-${item.slug}.png', 400);
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'No se pudo descargar el código QR.');
    }
  }

  Future<void> _saveQrPng(String text, String fileName, double size) async {
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
    final exportSize = size * 2; // 2x the on-screen size for a sharper PNG.
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
    if (kIsWeb) {
      // Direct browser download straight to Descargas — sharing on web
      // opens the OS's native "Compartir" dialog when the Web Share API
      // with files is available (e.g. Windows/Edge), which isn't what a
      // "Descargar imagen" button should do.
      downloadBytes(bytes, fileName, 'image/png');
    } else {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: fileName, mimeType: 'image/png')],
          fileNameOverrides: [fileName],
          text: fileName,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final generator = Container(
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
              Flexible(
                child: Text(
                  'Generador de Códigos QR',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
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
          if (_isVinnyLink) ...[
            const SizedBox(height: 12),
            _CartaToggle(
              value: _makeCarta,
              onChanged: _isBuildingCarta ? null : (v) => setState(() => _makeCarta = v),
            ),
            if (_makeCarta) ...[
              const SizedBox(height: 12),
              Text('Precios', style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'domicilio',
                    label: Text('Domicilio'),
                    icon: Icon(LucideIcons.bike, size: 16),
                  ),
                  ButtonSegment(
                    value: 'mesa',
                    label: Text('Mesa'),
                    icon: Icon(LucideIcons.utensils, size: 16),
                  ),
                ],
                selected: {_precios},
                onSelectionChanged:
                    _isBuildingCarta ? null : (s) => setState(() => _precios = s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
            ],
          ],
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
            onPressed: _isBuildingCarta ? null : _generate,
            child: _isBuildingCarta
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Leyendo el menú en Vinny…'),
                    ],
                  )
                : Text(_willMakeCarta ? 'Crear carta y QR' : 'Generar QR'),
          ),
          if (_isBuildingCarta) ...[
            const SizedBox(height: 8),
            Text(
              'Puede tardar hasta un minuto mientras se preparan las fotos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
          if (_generatedText != null) ...[
            if (_carta != null) ...[
              const SizedBox(height: 24),
              _CartaSummary(
                carta: _carta!,
                onOpen: () => _openUrl(_carta!.url),
                onCopy: () => _copyLink(_carta!.url),
              ),
            ],
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
    );

    final cartas = _CartasPanel(
      cartas: _cartas,
      busySlug: _deletingSlug ?? _refreshingSlug,
      onDownload: _downloadCartaQr,
      onRefresh: _refreshCarta,
      onOpen: (c) => _openUrl(c.url),
      onCopy: (c) => _copyLink(c.url),
      onDelete: _deleteCarta,
    );

    // Dos columnas cuando hay ancho: el generador a la izquierda y las
    // cartas a la derecha, cada uno con su propio desplazamiento, para que
    // una lista larga de cartas no empuje el formulario. En celular, una
    // sola columna: el generador arriba y las cartas debajo.
    final body = LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 960) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 440,
                  child: SingleChildScrollView(child: generator),
                ),
                const SizedBox(width: 16),
                Expanded(child: SingleChildScrollView(child: cartas)),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppLayout.contentMaxWidthNarrow),
              child: Column(
                children: [generator, const SizedBox(height: 16), cartas],
              ),
            ),
          ),
        );
      },
    );

    if (!widget.showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Generador de QR')),
      body: body,
    );
  }
}

class _CartaResult {
  const _CartaResult({
    required this.url,
    required this.nombre,
    required this.categorias,
    required this.productos,
    required this.conFoto,
  });

  factory _CartaResult.fromMap(Map<String, dynamic> m) => _CartaResult(
        url: m['url'] as String,
        nombre: (m['nombre'] as String?) ?? '',
        categorias: (m['categorias'] as num?)?.toInt() ?? 0,
        productos: (m['productos'] as num?)?.toInt() ?? 0,
        conFoto: (m['conFoto'] as num?)?.toInt() ?? 0,
      );

  final String url;
  final String nombre;
  final int categorias;
  final int productos;
  final int conFoto;

  String get slug => Uri.parse(url).pathSegments.last;

  String get displayName => _asName(nombre);
}

/// VinApp stores names in capitals ("CELENA"); show them as a name.
String _asName(String raw) => raw
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

class _CartaListItem {
  const _CartaListItem({
    required this.slug,
    required this.nombre,
    required this.url,
    required this.vinnyUrl,
    required this.generadoEn,
    required this.productos,
    required this.bytes,
    required this.precios,
  });

  factory _CartaListItem.fromMap(Map<String, dynamic> m) => _CartaListItem(
        slug: m['slug'] as String,
        nombre: (m['nombre'] as String?) ?? (m['slug'] as String),
        url: m['url'] as String,
        vinnyUrl: (m['vinnyUrl'] as String?) ??
            'https://vinny.vinapp.co/?company=${m['slug']}',
        generadoEn: DateTime.tryParse((m['generadoEn'] as String?) ?? '')?.toLocal(),
        productos: (m['productos'] as num?)?.toInt() ?? 0,
        bytes: (m['bytes'] as num?)?.toInt() ?? 0,
        precios: (m['precios'] as String?) ?? 'domicilio',
      );

  final String slug;
  final String nombre;
  final String url;
  final String vinnyUrl;
  final DateTime? generadoEn;
  final int productos;
  final int bytes;

  /// "domicilio" o "mesa".
  final String precios;

  String get displayName => _asName(nombre);
}

String _formatMb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return '${NumberFormat(mb < 10 ? '0.0' : '0', 'es').format(mb)} MB';
}

/// "Cartas creadas": una tarjeta por restaurante con su QR ya dibujado y
/// todo lo que se hace con una carta a un clic, sin volver a pegar el enlace.
class _CartasPanel extends StatelessWidget {
  const _CartasPanel({
    required this.cartas,
    required this.busySlug,
    required this.onDownload,
    required this.onRefresh,
    required this.onOpen,
    required this.onCopy,
    required this.onDelete,
  });

  /// Null mientras carga la primera vez.
  final List<_CartaListItem>? cartas;

  /// Carta que se está borrando o actualizando: sus botones esperan.
  final String? busySlug;
  final ValueChanged<_CartaListItem> onDownload;
  final ValueChanged<_CartaListItem> onRefresh;
  final ValueChanged<_CartaListItem> onOpen;
  final ValueChanged<_CartaListItem> onCopy;
  final ValueChanged<_CartaListItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final list = cartas;
    final totalBytes = list?.fold<int>(0, (n, c) => n + c.bytes) ?? 0;

    Widget content;
    if (list == null) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (list.isEmpty) {
      content = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(LucideIcons.bookOpen, size: 28, color: colors.textSecondary),
            const SizedBox(height: 10),
            Text(
              'Aún no hay cartas',
              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Pega un enlace de Vinny en el generador para crear la primera.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      );
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final columns = (constraints.maxWidth / 230).floor().clamp(1, 4);
          final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final c in list)
                SizedBox(
                  width: tileWidth,
                  child: _CartaTile(
                    carta: c,
                    busy: busySlug == c.slug,
                    locked: busySlug != null,
                    onDownload: () => onDownload(c),
                    onRefresh: () => onRefresh(c),
                    onOpen: () => onOpen(c),
                    onCopy: () => onCopy(c),
                    onDelete: () => onDelete(c),
                  ),
                ),
            ],
          );
        },
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
            children: [
              Icon(LucideIcons.bookOpen, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cartas creadas',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (list != null && list.isNotEmpty)
                Text(
                  '${list.length} ${list.length == 1 ? 'carta' : 'cartas'} · ${_formatMb(totalBytes)}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 16),
          content,
        ],
      ),
    );
  }
}

class _CartaTile extends StatelessWidget {
  const _CartaTile({
    required this.carta,
    required this.busy,
    required this.locked,
    required this.onDownload,
    required this.onRefresh,
    required this.onOpen,
    required this.onCopy,
    required this.onDelete,
  });

  final _CartaListItem carta;
  final bool busy;
  final bool locked;
  final VoidCallback onDownload;
  final VoidCallback onRefresh;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fecha = carta.generadoEn != null
        ? DateFormat("d 'de' MMM", 'es').format(carta.generadoEn!)
        : null;

    Widget action(IconData icon, String tooltip, VoidCallback onPressed, {Color? color}) {
      return IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: locked ? null : onPressed,
        icon: Icon(icon, size: 17, color: locked ? null : (color ?? colors.textSecondary)),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: busy
                ? const SizedBox(
                    height: 112,
                    width: 112,
                    child: Center(
                      child: SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : QrImageView(
                    data: carta.url,
                    size: 112,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    gapless: true,
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            carta.displayName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _PreciosChip(precios: carta.precios),
          const SizedBox(height: 4),
          Text(
            [
              if (carta.productos > 0) '${carta.productos} productos',
              ?fecha,
            ].join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              action(LucideIcons.download, 'Descargar QR', onDownload),
              action(LucideIcons.refreshCw, 'Actualizar precios', onRefresh),
              action(LucideIcons.externalLink, 'Abrir carta', onOpen),
              action(LucideIcons.copy, 'Copiar enlace', onCopy),
              action(LucideIcons.trash2, 'Borrar carta', onDelete, color: colors.error),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartaToggle extends StatelessWidget {
  const _CartaToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.bookOpen, size: 18, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crear carta digital',
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Es un enlace de Vinny: se arma una carta con fotos y precios, '
                  'sin pedidos, y el QR abre esa carta.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _CartaSummary extends StatelessWidget {
  const _CartaSummary({required this.carta, required this.onOpen, required this.onCopy});

  final _CartaResult carta;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sinFoto = carta.productos - carta.conFoto;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.checkCircle2, size: 18, color: colors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Carta de ${carta.displayName} lista',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${carta.categorias} categorías · ${carta.productos} productos'
            '${sinFoto > 0 ? ' · $sinFoto sin foto' : ''}',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 8),
          SelectableText(
            carta.url,
            style: TextStyle(color: colors.primary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Los precios quedan como están hoy en VinApp. Si cambian, vuelve a '
            'crear la carta: el enlace y el QR siguen siendo los mismos.',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(LucideIcons.externalLink, size: 16),
                label: const Text('Abrir carta'),
              ),
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(LucideIcons.copy, size: 16),
                label: const Text('Copiar enlace'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreciosChip extends StatelessWidget {
  const _PreciosChip({required this.precios});

  final String precios;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mesa = precios == 'mesa';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: ShapeDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mesa ? LucideIcons.utensils : LucideIcons.bike, size: 12, color: colors.primary),
          const SizedBox(width: 4),
          Text(
            mesa ? 'Precios de mesa' : 'Precios de domicilio',
            style: TextStyle(color: colors.primary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
