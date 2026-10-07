import 'package:http/http.dart' as http;

import '../core/utils/vinapp_reports.dart';

/// Lo que quedó de una descarga, listo para entregar.
class VinAppDownload {
  const VinAppDownload({
    required this.fileName,
    required this.bytes,
    required this.registros,
  });

  final String fileName;
  final List<int> bytes;

  /// Filas de datos, sin contar el encabezado. Se muestra al terminar: una
  /// licencia vacía descarga un archivo perfectamente válido con cero filas, y
  /// sin este número eso parece un éxito.
  final int registros;
}

/// Falla esperable de una descarga, con un texto que se le puede mostrar a
/// quien está usando la pantalla.
class VinAppDownloadException implements Exception {
  const VinAppDownloadException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Trae un reporte de VinApp y lo devuelve ya reformateado.
///
/// Va directo del navegador a `alfa.vinapp.co`, sin pasar por una Cloud
/// Function. No es un atajo: la API de VinApp responde
/// `Access-Control-Allow-Origin` con el origen que le pidan, así que el
/// navegador tiene permiso para llamarla. Hacerlo por el servidor habría
/// sumado una dependencia de las Cloud Functions, que hoy están caídas porque
/// la facturación del proyecto está deshabilitada — esta pantalla funciona
/// igual mientras eso siga así.
class VinAppDownloadService {
  const VinAppDownloadService({this.client});

  /// Inyectable para probar sin red.
  final http.Client? client;

  Future<VinAppDownload> descargar({
    required VinAppReport report,
    required String licencia,
  }) async {
    final id = licencia.trim();
    if (id.isEmpty) {
      throw const VinAppDownloadException('Escribe el ID de la licencia.');
    }

    final c = client ?? http.Client();
    final http.Response res;
    try {
      res = await c
          .get(Uri.parse(report.urlPara(id)))
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw VinAppDownloadException(
        'No se pudo conectar con VinApp. Revisa tu conexión e inténtalo de '
        'nuevo. ($e)',
      );
    } finally {
      if (client == null) c.close();
    }

    if (res.statusCode == 404) {
      throw VinAppDownloadException(
        'VinApp no encontró el reporte de ${report.titulo.toLowerCase()} para '
        'la licencia $id.',
      );
    }
    if (res.statusCode != 200) {
      throw VinAppDownloadException(
        'VinApp respondió ${res.statusCode} al pedir '
        '${report.titulo.toLowerCase()} de la licencia $id.',
      );
    }
    if (res.bodyBytes.isEmpty) {
      throw VinAppDownloadException(
        'VinApp devolvió un archivo vacío para la licencia $id.',
      );
    }
    // Un .xlsx es un zip: empieza por "PK". Cuando la licencia no existe, la
    // API a veces contesta 200 con una página de error en HTML, y sin esta
    // comprobación eso se descargaría con extensión .xlsx y reventaría recién
    // al abrirlo.
    if (res.bodyBytes.length < 4 ||
        res.bodyBytes[0] != 0x50 ||
        res.bodyBytes[1] != 0x4B) {
      throw VinAppDownloadException(
        'VinApp no devolvió un Excel para la licencia $id. Revisa que el ID '
        'sea correcto.',
      );
    }

    final ({List<int> bytes, int registros}) libro;
    try {
      libro = reformatVinAppWorkbook(
        sourceBytes: res.bodyBytes,
        report: report,
        licencia: id,
        generadoEl: DateTime.now(),
      );
    } catch (e) {
      throw VinAppDownloadException(
        'El archivo llegó bien pero no se pudo reformatear: $e',
      );
    }

    return VinAppDownload(
      fileName: report.nombreArchivo(id, DateTime.now()),
      bytes: libro.bytes,
      registros: libro.registros,
    );
  }
}
