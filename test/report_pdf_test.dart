import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Guards the PDF's two failure modes that nothing else would catch.
///
/// A PDF fails quietly: bytes are produced, a file downloads, and the viewer
/// shows blank boxes where the accents should be, or refuses the file. The
/// output of this same setup was opened with an independent reader (Python's
/// pypdf), which found the text extractable with "Panadería", "INSTALACIÓN"
/// and "Observación con ñ" intact, and Plus Jakarta Sans embedded with its
/// character map — so search inside the document works. These tests pin what
/// made that true.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<pw.ThemeData> tema() async => pw.ThemeData.withFont(
    base: pw.Font.ttf(
      await rootBundle.load('assets/fonts/PlusJakartaSans-400.ttf'),
    ),
    bold: pw.Font.ttf(
      await rootBundle.load('assets/fonts/PlusJakartaSans-700.ttf'),
    ),
  );

  test('la tipografía de la app se puede incrustar', () async {
    // Si el asset se renombra o sale del pubspec, el reporte cae aquí y no en
    // producción — y el respaldo del paquete sólo cubre Latin-1, así que la
    // falla se vería como cuadros vacíos en los nombres, no como un error.
    await expectLater(tema(), completes);
  });

  test('genera un PDF válido con texto acentuado y varias páginas', () async {
    final doc = pw.Document(theme: await tema());
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('Reporte de CheCu'),
          pw.TableHelper.fromTextArray(
            headers: const ['Cliente', 'Teléfono', 'Última tarea'],
            data: [
              for (var i = 0; i < 120; i++)
                ['Panadería los andes $i', '3005551234', 'INSTALACIÓN'],
            ],
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final cabecera = String.fromCharCodes(bytes.take(5));
    final cola = String.fromCharCodes(bytes.skip(bytes.length - 8));

    expect(cabecera, '%PDF-', reason: 'no es un PDF');
    expect(cola.trim(), endsWith('%%EOF'), reason: 'el archivo quedó truncado');
    expect(
      bytes.length,
      greaterThan(5000),
      reason: 'un PDF con 120 filas y una fuente incrustada no puede ser mínimo',
    );
  });
}
