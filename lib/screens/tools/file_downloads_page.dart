import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/file_delivery.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../core/utils/vinapp_reports.dart';
import '../../providers/auth_provider.dart';
import '../../services/vinapp_download_service.dart';
import '../../widgets/loading_indicator.dart';

/// Descarga los listados de VinApp y los entrega con un formato usable.
///
/// Cada listado lleva su propio campo de licencia. La primera versión tenía un
/// solo ID arriba y las tres tarjetas debajo, y era otra cosa: obligaba a
/// pensar en "la licencia que estoy mirando" cuando lo que uno hace es ir a
/// buscar *un* listado concreto. Separados, cada fila es una tarea completa —
/// pego el ID donde dice Clientes y descargo clientes— y de paso se pueden
/// pedir listados de licencias distintas sin borrar nada.
///
/// Los archivos que VinApp entrega son correctos pero crudos: la hoja se llama
/// "Worksheet", el encabezado no se distingue, las columnas miden todas lo
/// mismo y los teléfonos vienen como número, así que Excel les quita los ceros
/// de la izquierda. Aquí se descargan con encabezado fijo y filtrable, anchos
/// reales, teléfonos como texto y los costos en pesos.
class FileDownloadsPage extends StatefulWidget {
  const FileDownloadsPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<FileDownloadsPage> createState() => _FileDownloadsPageState();
}

class _FileDownloadsPageState extends State<FileDownloadsPage> {
  late final Map<VinAppReport, TextEditingController> _licencias = {
    for (final r in VinAppReport.values) r: TextEditingController(),
  };
  final _service = const VinAppDownloadService();

  final _enCurso = <VinAppReport>{};
  final _resultados = <VinAppReport, String>{};

  @override
  void dispose() {
    for (final c in _licencias.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _descargar(VinAppReport report) async {
    final id = _licencias[report]!.text.trim();
    if (id.isEmpty) return;

    setState(() {
      _enCurso.add(report);
      _resultados.remove(report);
    });

    try {
      final r = await _service.descargar(report: report, licencia: id);
      await deliverFile(
        fileName: r.fileName,
        bytes: r.bytes,
        mimeType: FileMime.xlsx,
      );
      if (!mounted) return;
      setState(() {
        _resultados[report] = r.registros == 0
            // Un archivo válido con cero filas se descarga igual de bien que
            // uno lleno; sin decirlo, parece que funcionó.
            ? 'Se descargó, pero la licencia $id no tiene registros.'
            : '${r.registros} registros · ${r.fileName}';
      });
    } on VinAppDownloadException catch (e) {
      if (!mounted) return;
      setState(() => _resultados[report] = e.message);
      SnackbarUtils.showError(context, e.message);
    } catch (e) {
      if (!mounted) return;
      final texto = 'No se pudo descargar: $e';
      setState(() => _resultados[report] = texto);
      SnackbarUtils.showError(context, texto);
    } finally {
      if (mounted) setState(() => _enCurso.remove(report));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // La entrada del menú ya está condicionada, pero la pantalla se protege
    // igual: una pantalla que confía en que nadie la abra por otro camino se
    // queda abierta el día que aparezca ese camino.
    final puede = context.watch<AuthProvider>().hasPermission(
      AppPermissions.downloadFiles,
    );
    if (!puede) {
      return const EmptyState(
        message:
            'No tienes acceso a la descarga de archivos. '
            'Pídeselo a un administrador.',
        icon: LucideIcons.lock,
      );
    }

    final cuerpo = SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Descargar archivos de VinApp',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Escribe el ID de la licencia en el listado que quieras y '
                'descárgalo. El Excel llega ya formateado: encabezado fijo, '
                'filtros y columnas legibles.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final report in VinAppReport.values) ...[
                _TarjetaReporte(
                  report: report,
                  controller: _licencias[report]!,
                  resultado: _resultados[report],
                  descargando: _enCurso.contains(report),
                  onDescargar: () => _descargar(report),
                  // Al cambiar el ID, el resultado anterior deja de
                  // corresponder: es de otra licencia.
                  onCambio: () {
                    if (_resultados.containsKey(report)) {
                      setState(() => _resultados.remove(report));
                    } else {
                      setState(() {});
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );

    if (!widget.showAppBar) return cuerpo;
    return Scaffold(
      appBar: AppBar(title: const Text('Descargar Archivos')),
      body: cuerpo,
    );
  }
}

class _TarjetaReporte extends StatelessWidget {
  const _TarjetaReporte({
    required this.report,
    required this.controller,
    required this.resultado,
    required this.descargando,
    required this.onDescargar,
    required this.onCambio,
  });

  final VinAppReport report;
  final TextEditingController controller;
  final String? resultado;
  final bool descargando;
  final VoidCallback onDescargar;
  final VoidCallback onCambio;

  IconData get _icono => switch (report) {
    VinAppReport.clientes => LucideIcons.users,
    VinAppReport.recetas => LucideIcons.chefHat,
    VinAppReport.adiciones => LucideIcons.plusCircle,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final angosto = context.isMobile;
    final listo = controller.text.trim().isNotEmpty && !descargando;

    final titulo = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(_icono, color: colors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                report.titulo,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                report.descripcion,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );

    final campo = TextField(
      controller: controller,
      enabled: !descargando,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textInputAction: TextInputAction.done,
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'ID de la licencia',
        prefixIcon: Icon(LucideIcons.hash, color: colors.primary, size: 16),
      ),
      onChanged: (_) => onCambio(),
      // Enter descarga: con el ID recién pegado, la mano ya está en el
      // teclado y buscar el botón con el mouse sobra.
      onSubmitted: (_) {
        if (controller.text.trim().isNotEmpty && !descargando) onDescargar();
      },
    );

    final boton = FilledButton.icon(
      onPressed: listo ? onDescargar : null,
      icon: descargando
          ? const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.download, size: 16),
      label: Text(descargando ? 'Descargando…' : 'Descargar'),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En un teléfono los tres no caben en una línea sin dejar el campo
          // del ID en unos pocos píxeles, así que bajan apilados.
          if (angosto) ...[
            titulo,
            const SizedBox(height: 10),
            campo,
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: boton),
          ] else
            Row(
              children: [
                Expanded(child: titulo),
                const SizedBox(width: 12),
                SizedBox(width: 190, child: campo),
                const SizedBox(width: 10),
                boton,
              ],
            ),
          if (resultado != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 14, color: colors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    resultado!,
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
