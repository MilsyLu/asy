import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/vinapp_reports.dart';

/// Pruebas del formateador de los reportes de VinApp.
///
/// Prueban la función real contra un libro armado aquí con la misma forma que
/// los archivos que VinApp entrega de verdad: hoja "Worksheet", encabezados en
/// mayúscula y con tilde, teléfonos guardados como número y costos como
/// decimal. Esa forma la saqué descargando los tres archivos reales y mirando
/// sus celdas, no del nombre de las columnas en una pantalla.
List<int> libroDeOrigen(
  List<String> encabezados,
  List<List<CellValue?>> filas,
) {
  final excel = Excel.createExcel();
  final hoja = excel['Worksheet'];
  excel.setDefaultSheet('Worksheet');
  for (final nombre in excel.tables.keys.toList()) {
    if (nombre != 'Worksheet') excel.delete(nombre);
  }
  hoja.appendRow([for (final h in encabezados) TextCellValue(h)]);
  for (final f in filas) {
    hoja.appendRow(f);
  }
  // `encode()` y no `save()`: en web, save() dispara además una descarga
  // suya llamada "FlutterExcel.xlsx". Ver excelBytes().
  return excel.encode()!;
}

void main() {
  final cuando = DateTime(2026, 10, 7, 11, 5);

  group('formatoDeColumna', () {
    test('el teléfono va como texto aunque llegue como número', () {
      // El origen lo manda como 3218863352. Dejarlo numérico le quita los
      // ceros de la izquierda y, por largo, Excel lo muestra como 3,21886E+09.
      expect(formatoDeColumna('TELEFONO'), FormatoColumna.texto);
      expect(formatoDeColumna('TELÉFONO'), FormatoColumna.texto);
      expect(formatoDeColumna('CÉDULA'), FormatoColumna.texto);
      expect(formatoDeColumna('TIPO DE IDENTIFICACIÓN'), FormatoColumna.texto);
    });

    test('reconoce la tilde del encabezado real', () {
      // Los archivos de VinApp traen "CATEGORÍA" y "ADICIÓN" con tilde. Una
      // comparación literal sin quitarlas fallaría justo en las columnas que
      // más importan.
      expect(formatoDeColumna('CATEGORÍA'), FormatoColumna.comoVenga);
      expect(formatoDeColumna('VALOR'), FormatoColumna.dinero);
      expect(formatoDeColumna('COSTO'), FormatoColumna.dinero);
      expect(formatoDeColumna('CANTIDAD'), FormatoColumna.decimal);
    });

    test('una columna que no conoce se deja como venga', () {
      // Si VinApp agrega una columna, no se le inventa un formato.
      expect(formatoDeColumna('ALGO NUEVO'), FormatoColumna.comoVenga);
      expect(formatoDeColumna('MERMA'), FormatoColumna.comoVenga);
    });
  });

  group('anchoDeColumna', () {
    test('una dirección pide más ancho que el resto', () {
      // El original deja las ocho columnas en 13 y una dirección completa se
      // ve cortada.
      expect(
        anchoDeColumna('DIRECCION'),
        greaterThan(anchoDeColumna('BARRIO')),
      );
      expect(anchoDeColumna('DIRECCIÓN'), anchoDeColumna('DIRECCION'));
      expect(anchoDeColumna('UNIDAD'), 16);
    });
  });

  group('urlPara / nombreArchivo', () {
    test('las tres salen de alfa', () {
      for (final r in VinAppReport.values) {
        expect(r.urlPara('7595'), startsWith('https://alfa.vinapp.co/api/'));
      }
    });

    test('arma la URL con el id de licencia al final', () {
      expect(
        VinAppReport.recetas.urlPara('7595'),
        'https://alfa.vinapp.co/api/report/export-recipes/7595',
      );
      expect(
        VinAppReport.clientes.urlPara('7041'),
        'https://alfa.vinapp.co/api/report/export-clients-history/7041',
      );
    });

    test('ignora los espacios que deja un pegado', () {
      expect(VinAppReport.adiciones.urlPara('  7595 '), endsWith('/7595'));
    });

    test('el nombre del archivo dice licencia y fecha', () {
      // Sin esto, dos descargas de licencias distintas llegan a Descargas con
      // el mismo nombre y la segunda se llama "(1)".
      expect(
        VinAppReport.recetas.nombreArchivo('7595', cuando),
        'VinApp_Recetas_7595_2026-10-07.xlsx',
      );
    });
  });

  group('reformatVinAppWorkbook', () {
    test('renombra la hoja y conserva todos los datos', () {
      final origen = libroDeOrigen(
        ['CATEGORÍA', 'PRODUCTO', 'CANTIDAD', 'COSTO'],
        [
          [
            TextCellValue('ARROZ'),
            TextCellValue('ARROZ DE POLLO'),
            DoubleCellValue(0.262),
            DoubleCellValue(3600),
          ],
          [
            TextCellValue('ARROZ'),
            TextCellValue('ARROZ DE POLLO'),
            DoubleCellValue(0.05),
            DoubleCellValue(7500),
          ],
        ],
      );

      final salida = reformatVinAppWorkbook(
        sourceBytes: origen,
        report: VinAppReport.recetas,
        licencia: '7595',
        generadoEl: cuando,
      ).bytes;

      final libro = Excel.decodeBytes(salida);
      expect(libro.tables.keys, contains('Recetas'));
      expect(libro.tables.keys, isNot(contains('Worksheet')));

      final hoja = libro.tables['Recetas']!;
      expect(hoja.rows.length, 3, reason: 'encabezado + dos filas');
      expect(hoja.rows[0][0]?.value.toString(), 'CATEGORÍA');
      expect(hoja.rows[1][1]?.value.toString(), 'ARROZ DE POLLO');
      expect((hoja.rows[1][2]?.value as DoubleCellValue).value, 0.262);
    });

    test('el teléfono numérico sale como texto, sin ".0" pegado', () {
      final origen = libroDeOrigen(
        ['NOMBRE', 'TELEFONO'],
        [
          [TextCellValue('sofia Aylin villa'), IntCellValue(3218863352)],
          [TextCellValue('Carlos daza'), DoubleCellValue(3016097118)],
        ],
      );

      final libro = Excel.decodeBytes(
        reformatVinAppWorkbook(
          sourceBytes: origen,
          report: VinAppReport.clientes,
          licencia: '7041',
          generadoEl: cuando,
        ).bytes,
      );
      final hoja = libro.tables['Clientes']!;
      expect(hoja.rows[1][1]?.value, isA<TextCellValue>());
      expect(hoja.rows[1][1]?.value.toString(), '3218863352');
      // Un double entero convertido de forma ingenua daría "3016097118.0".
      expect(hoja.rows[2][1]?.value.toString(), '3016097118');
    });

    test('agrega la hoja de información con licencia y origen', () {
      final libro = Excel.decodeBytes(
        reformatVinAppWorkbook(
          sourceBytes: libroDeOrigen(
            ['PRODUCTO'],
            [
              [TextCellValue('ARROZ')],
            ],
          ),
          report: VinAppReport.adiciones,
          licencia: '7595',
          generadoEl: cuando,
        ).bytes,
      );
      final info = libro.tables['Información']!;
      final texto = info.rows
          .map((f) => f.map((c) => c?.value?.toString() ?? '').join(' '))
          .join('\n');
      expect(texto, contains('7595'));
      expect(texto, contains('export-additions'));
      expect(texto, contains('7/10/2026'));
    });

    test('descarta las filas totalmente vacías del final', () {
      // El original suele traerlas; dentro de una tabla el filtro empieza a
      // contarlas como datos.
      final origen = libroDeOrigen(
        ['PRODUCTO', 'VALOR'],
        [
          [TextCellValue('ARROZ'), IntCellValue(1000)],
          [null, null],
          [null, null],
        ],
      );
      final libro = Excel.decodeBytes(
        reformatVinAppWorkbook(
          sourceBytes: origen,
          report: VinAppReport.adiciones,
          licencia: '7595',
          generadoEl: cuando,
        ).bytes,
      );
      expect(libro.tables['Adiciones']!.rows.length, 2);
    });

    test('un encabezado vacío no rompe el archivo', () {
      // Excel rechaza el libro entero si una columna de la tabla no tiene
      // nombre, y lo hace al abrirlo: no hay forma de enterarse antes.
      final libro = Excel.decodeBytes(
        reformatVinAppWorkbook(
          sourceBytes: libroDeOrigen(
            ['PRODUCTO', ''],
            [
              [TextCellValue('ARROZ'), TextCellValue('x')],
            ],
          ),
          report: VinAppReport.recetas,
          licencia: '7595',
          generadoEl: cuando,
        ).bytes,
      );
      final cab = libro.tables['Recetas']!.rows[0];
      expect(cab[1]?.value.toString(), isNotEmpty);
    });

    test('un libro sin filas no revienta', () {
      final salida = reformatVinAppWorkbook(
        sourceBytes: libroDeOrigen(['PRODUCTO'], const []),
        report: VinAppReport.recetas,
        licencia: '7595',
        generadoEl: cuando,
      ).bytes;
      expect(salida, isNotEmpty);
      expect(Excel.decodeBytes(salida).tables.keys, contains('Recetas'));
    });
  });
}
