import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/excel_export.dart';

/// Round-trips a workbook through the same helpers the report uses.
///
/// A spreadsheet fails differently from the rest of the app: nothing throws,
/// a file downloads, and Excel refuses it — or worse, opens it with the
/// accents mangled or a column silently shifted. None of that shows up in
/// `flutter analyze`, and none of it is visible until somebody double-clicks
/// the file. Encoding and decoding here is the cheapest way to know the bytes
/// are a real `.xlsx` and that what went in is what comes out.
void main() {
  test('el libro se codifica y se vuelve a leer con su contenido', () {
    final excel = Excel.createExcel();
    final sheet = excel['Tareas'];
    writeHeader(sheet, const ['Fecha', 'Cliente', 'Reprogramaciones']);
    sheet.appendRow([
      TextCellValue('2026-08-15'),
      TextCellValue('Panadería los andes'),
      IntCellValue(3),
    ]);
    excel.delete('Sheet1');

    final bytes = excel.encode();
    expect(bytes, isNotNull, reason: 'sin bytes no hay archivo que entregar');

    final leido = Excel.decodeBytes(bytes!);
    expect(leido.tables.keys, contains('Tareas'));
    expect(
      leido.tables.keys,
      isNot(contains('Sheet1')),
      reason: 'la hoja vacía que crea el paquete no debe viajar en el archivo',
    );

    final filas = leido.tables['Tareas']!.rows;
    expect(filas.first.map((c) => c?.value.toString()), [
      'Fecha',
      'Cliente',
      'Reprogramaciones',
    ]);

    final datos = filas[1];
    expect(datos[0]?.value.toString(), '2026-08-15');
    expect(
      datos[1]?.value.toString(),
      'Panadería los andes',
      reason: 'las tildes y la ñ tienen que sobrevivir el viaje',
    );
    expect(
      datos[2]?.value,
      isA<IntCellValue>(),
      reason: 'un número tiene que llegar como número, no como texto: '
          'si no, no se puede sumar en Excel',
    );
  });

  test('el encabezado queda con el estilo de marca', () {
    final excel = Excel.createExcel();
    final sheet = excel['Hoja'];
    writeHeader(sheet, const ['Uno', 'Dos']);

    final celda = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    );
    expect(celda.cellStyle?.isBold, isTrue);
  });
}
