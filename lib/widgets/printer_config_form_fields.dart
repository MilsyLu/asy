import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/constants/printer_config_schema.dart';
import '../core/responsive/app_spacing.dart';
import '../core/theme/theme_colors.dart';
import '../core/utils/snackbar_utils.dart';
import '../services/clipboard_image_web_stub.dart'
    if (dart.library.js_interop) '../services/clipboard_image_web.dart';
import '../services/printer_config_repository.dart';

/// One value input for a [PrinterConfigFieldSchema] entry: the full label
/// always rendered above the field (never inside a cramped `labelText`,
/// which was truncating long labels like "Impresora de comandas 1" in a
/// narrow grid cell) and the input itself below.
class _PrinterConfigFieldTile extends StatelessWidget {
  const _PrinterConfigFieldTile({
    required this.schema,
    required this.values,
    required this.onChanged,
  });

  final PrinterConfigFieldSchema schema;
  final Map<String, dynamic> values;
  final void Function(String key, dynamic value) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget field;
    switch (schema.type) {
      case PrinterConfigFieldType.text:
        field = TextFormField(
          key: ValueKey(schema.key),
          initialValue: values[schema.key] as String? ?? '',
          style: TextStyle(color: colors.textPrimary, fontSize: 13),
          decoration: InputDecoration(isDense: true, hintText: schema.placeholder),
          onChanged: (v) => onChanged(schema.key, v),
        );
      case PrinterConfigFieldType.number:
        field = TextFormField(
          key: ValueKey(schema.key),
          initialValue: (values[schema.key] as num?)?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          style: TextStyle(color: colors.textPrimary, fontSize: 13),
          decoration: const InputDecoration(isDense: true),
          onChanged: (v) => onChanged(schema.key, num.tryParse(v)),
        );
      case PrinterConfigFieldType.dropdown:
        final current = values[schema.key] as String?;
        field = DropdownButtonFormField<String>(
          key: ValueKey(schema.key),
          initialValue: schema.dropdownOptions.contains(current) ? current : null,
          dropdownColor: colors.surface,
          isDense: true,
          decoration: const InputDecoration(isDense: true),
          items: schema.dropdownOptions
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => onChanged(schema.key, v),
        );
      case PrinterConfigFieldType.boolean:
        // Handled by _PrinterConfigToggleTile instead — kept here only so
        // the switch is exhaustive.
        field = const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Fixed height regardless of 1 vs 2 line labels — otherwise tiles in
        // the same visual row sit at different Y offsets depending on
        // whether their label wrapped, which reads as a crooked/misaligned
        // grid (reported by Michel). Every tile reserves the same 2-line
        // block so the field input below always starts at the same height.
        SizedBox(
          height: 30,
          child: Text(
            schema.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 4),
        field,
      ],
    );
  }
}

/// Compact toggle for a boolean field — checkbox + label side by side in a
/// bordered chip, sized to content rather than stretched, so a whole row of
/// short Si/No toggles reads as a scannable group instead of being mixed in
/// with the wider text fields.
class _PrinterConfigToggleTile extends StatelessWidget {
  const _PrinterConfigToggleTile({
    required this.schema,
    required this.values,
    required this.onChanged,
  });

  final PrinterConfigFieldSchema schema;
  final Map<String, dynamic> values;
  final void Function(String key, dynamic value) onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = values[schema.key] as bool? ?? false;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(schema.key, !value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: value ? colors.primary.withValues(alpha: 0.1) : colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: value ? colors.primary.withValues(alpha: 0.5) : colors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(schema.key, v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                schema.label,
                style: TextStyle(color: colors.textPrimary, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One section's header + its fields, grouped into a bordered card:
/// booleans first (a compact wrapped grid of toggle chips), then text/
/// number/dropdown fields (a responsive multi-column grid, each field's
/// full label rendered above its input so nothing truncates).
class PrinterConfigSectionGroup extends StatelessWidget {
  const PrinterConfigSectionGroup({
    super.key,
    required this.section,
    required this.values,
    required this.onChanged,
    this.searchQuery = '',
  });

  final String section;
  final Map<String, dynamic> values;
  final void Function(String key, dynamic value) onChanged;

  /// When non-empty, only fields whose label contains this (case-
  /// insensitive) are shown — the whole section card is hidden if none
  /// match. Powers the "buscar un campo" bar in the form's header.
  final String searchQuery;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final query = searchQuery.trim().toLowerCase();
    final fields = PrinterConfigSchema.forSection(section)
        .where((f) => query.isEmpty || f.label.toLowerCase().contains(query))
        .toList();
    if (fields.isEmpty) return const SizedBox.shrink();
    final toggles = fields.where((f) => f.type == PrinterConfigFieldType.boolean).toList();
    final inputs = fields.where((f) => f.type != PrinterConfigFieldType.boolean).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            PrinterConfigSections.labels[section] ?? section,
            style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const Divider(height: AppSpacing.lg),
          if (toggles.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in toggles)
                  _PrinterConfigToggleTile(schema: f, values: values, onChanged: onChanged),
              ],
            ),
            if (inputs.isNotEmpty) const SizedBox(height: AppSpacing.md),
          ],
          if (inputs.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = AppSpacing.md;
                const minTileWidth = 200.0;
                final columns = (constraints.maxWidth / minTileWidth).floor().clamp(1, 4);
                final tileWidth = (constraints.maxWidth - spacing * (columns - 1)) / columns;
                // Compact fields (short content: numbers, "Normal",
                // "Comanda"...) get half the width so two fit where one
                // full-width field did — Michel's "aprovechar el máximo
                // espacio" preference for the general section's non-printer
                // fields.
                final compactWidth = (tileWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final f in inputs)
                      SizedBox(
                        width: f.compact ? compactWidth : tileWidth,
                        child: _PrinterConfigFieldTile(schema: f, values: values, onChanged: onChanged),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PickedImage {
  const _PickedImage({required this.id, required this.bytes, required this.mediaType});

  final String id;
  final Uint8List bytes;
  final String mediaType;
}

/// Picks 1+ screenshots (from a saved file, or pasted directly from the
/// clipboard with Ctrl+V — common after a Win+Shift+S snip), shows
/// removable thumbnails, and — on "Analizar con IA" — sends them to
/// [PrinterConfigRepository.extractFromImages] and hands the (possibly
/// partial) result to [onExtracted] for the caller to merge into the form.
/// Never uploads/stores the images anywhere; they're dropped from memory as
/// soon as this widget is done with them.
class PrinterConfigImagePicker extends StatefulWidget {
  const PrinterConfigImagePicker({
    super.key,
    required this.repository,
    required this.onExtracted,
  });

  final PrinterConfigRepository repository;
  final void Function(Map<String, dynamic> extracted) onExtracted;

  @override
  State<PrinterConfigImagePicker> createState() => _PrinterConfigImagePickerState();
}

class _PrinterConfigImagePickerState extends State<PrinterConfigImagePicker> {
  static const int _maxImages = 6;
  int _nextId = 0;

  final List<_PickedImage> _picked = [];
  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      registerClipboardImageListener(_addBytes);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      unregisterClipboardImageListener();
    }
    super.dispose();
  }

  void _addBytes(Uint8List bytes, String mediaType) {
    if (!mounted) return;
    if (_picked.length >= _maxImages) {
      SnackbarUtils.showError(context, 'Máximo $_maxImages capturas por análisis.');
      return;
    }
    setState(() => _picked.add(_PickedImage(id: 'img${_nextId++}', bytes: bytes, mediaType: mediaType)));
  }

  Future<void> _pickFromFiles() async {
    final result = await ImagePicker().pickMultiImage(imageQuality: 70, maxWidth: 1600);
    if (result.isEmpty) return;
    if (_picked.length + result.length > _maxImages) {
      if (mounted) SnackbarUtils.showError(context, 'Máximo $_maxImages capturas por análisis.');
      return;
    }
    for (final x in result) {
      final bytes = await x.readAsBytes();
      _addBytes(bytes, x.mimeType ?? 'image/jpeg');
    }
  }

  void _remove(_PickedImage image) {
    setState(() => _picked.remove(image));
  }

  Future<void> _analyze() async {
    if (_picked.isEmpty) return;
    setState(() => _analyzing = true);
    try {
      final images = _picked
          .map((i) => PrinterConfigImageInput(base64Data: base64Encode(i.bytes), mediaType: i.mediaType))
          .toList();
      final extracted = await widget.repository.extractFromImages(images);
      widget.onExtracted(extracted);
      if (mounted) {
        SnackbarUtils.showSuccess(
            context, '${extracted.length} campo(s) reconocidos — revísalos antes de guardar');
        setState(() => _picked.clear());
      }
    } catch (e) {
      if (mounted) SnackbarUtils.showError(context, SnackbarUtils.firebaseErrorMessage(e));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  static const String _tooltip =
      'Sube una o varias capturas de la pantalla de configuración de VinApp '
      'Print, o pégalas con Ctrl+V (por ejemplo después de recortar con '
      'Win+Shift+S) — no hace falta guardarlas primero. Como VinApp Print no '
      'es responsivo, puede que necesites varias capturas para cubrir toda '
      'la pantalla, o solo una si quieres actualizar una parte. Las '
      'capturas nunca se guardan, solo se usan para llenar el formulario.';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Deliberately no card/border here — this used to be a bordered panel
    // with a full paragraph of explanation, which pushed the rest of the
    // (already long, 85-field) form below the fold. Kept to a single row
    // of controls plus an info tooltip for the explanation, since Michel
    // wants the header to cost as little vertical space as possible.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: _analyzing ? null : _pickFromFiles,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Elegir capturas'),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElevatedButton.icon(
              onPressed: (_analyzing || _picked.isEmpty) ? null : _analyze,
              icon: _analyzing
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Analizar con IA'),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: _tooltip,
              triggerMode: TooltipTriggerMode.tap,
              child: Icon(Icons.info_outline, size: 18, color: colors.textSecondary),
            ),
          ],
        ),
        if (_picked.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final image in _picked)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(image.bytes, width: 56, height: 56, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: InkWell(
                        onTap: () => _remove(image),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: colors.error,
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
