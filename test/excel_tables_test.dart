import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow_executive/core/utils/excel_export.dart';
import 'package:taskflow_executive/core/utils/excel_tables.dart';

/// Guards the hand-written table parts.
///
/// `excel` 4.0.6 cannot make Excel tables, so `addExcelTables` writes the four
/// coordinated pieces into the package itself. Excel is unforgiving here: one
/// wrong relationship id, a missing content type, or `<tableParts>` in the
/// wrong position and it offers to "repair" the file instead of opening it —
/// and nothing on the Dart side would have complained.
///
/// The output of this same code was checked against a strict independent
/// reader (Python's openpyxl), which found three tables with their filters and
/// striping and read the accents back intact. These tests pin the structure
/// that made that true, so a future change cannot quietly undo it.
void main() {
  ({List<int> bytes, Archive zip}) construir() {
    final excel = Excel.createExcel();

    final tareas = excel['Tareas'];
    writeHeader(tareas, const ['Fecha', 'Teléfono']);
    tareas.appendRow([
      TextCellValue('2026-08-15'),
      TextCellValue('Panadería los andes'),
    ]);

    // Second sheet on purpose: the package only writes a rels part for the
    // first one, so this is the case that needs the file created from scratch.
    final clientes = excel['Clientes'];
    writeHeader(clientes, const ['Cliente', 'Tareas']);
    clientes.appendRow([TextCellValue('X'), IntCellValue(1)]);

    excel.delete('Sheet1');

    final bytes = addExcelTables(excel.encode()!, const [
      TableSpec(sheet: 'Tareas', headers: ['Fecha', 'Teléfono'], dataRows: 1),
      TableSpec(sheet: 'Clientes', headers: ['Cliente', 'Tareas'], dataRows: 1),
    ]);
    return (bytes: bytes, zip: ZipDecoder().decodeBytes(bytes));
  }

  String leer(Archive zip, String nombre) {
    final f = zip.files.firstWhere((f) => f.name == nombre);
    // utf8.decode y no String.fromCharCodes: leer bytes UTF-8 como Latin-1
    // convierte "Teléfono" en "TelÃ©fono". Es el mismo error que tenía el
    // código que estas pruebas vigilan.
    return utf8.decode(f.content as List<int>);
  }

  test('escribe una definición de tabla por hoja', () {
    final r = construir();
    final nombres = r.zip.files.map((f) => f.name);
    expect(nombres, contains('xl/tables/table1.xml'));
    expect(nombres, contains('xl/tables/table2.xml'));

    final tabla = leer(r.zip, 'xl/tables/table1.xml');
    expect(tabla, contains('<autoFilter ref="A1:B2"/>'));
    expect(
      tabla,
      contains('name="Teléfono"'),
      reason: 'Excel exige que el nombre de columna coincida con el encabezado',
    );
    expect(tabla, contains('showRowStripes="1"'));
  });

  test('cada hoja apunta a su tabla y el tipo está declarado', () {
    final r = construir();

    // Sin el tipo de contenido la parte existe en el zip y Excel no la ve.
    final tipos = leer(r.zip, '[Content_Types].xml');
    expect(tipos, contains('/xl/tables/table1.xml'));
    expect(tipos, contains('spreadsheetml.table+xml'));

    for (final sheet in ['sheet1', 'sheet2']) {
      final xml = leer(r.zip, 'xl/worksheets/$sheet.xml');
      expect(
        xml,
        contains('<tableParts count="1">'),
        reason: 'la hoja tiene que referenciar su tabla',
      );
      expect(
        xml.indexOf('<tableParts'),
        greaterThan(xml.indexOf('<pageMargins')),
        reason: 'Excel valida el orden de los hijos y rechaza el archivo '
            'si tableParts aparece antes de tiempo',
      );

      final rels = leer(r.zip, 'xl/worksheets/_rels/$sheet.xml.rels');
      final relId = RegExp(
        'Id="([^"]+)"[^>]*relationships/table"',
      ).firstMatch(rels)?.group(1);
      expect(relId, isNotNull, reason: 'falta la relación hacia la tabla');
      expect(
        xml,
        contains('r:id="$relId"'),
        reason: 'el id usado en la hoja tiene que ser el de su propia relación',
      );
    }
  });

  test('no pisa la relación que la primera hoja ya traía', () {
    final r = construir();
    final rels = leer(r.zip, 'xl/worksheets/_rels/sheet1.xml.rels');
    // El paquete le pone un dibujo en rId1; reutilizar ese id rompe las dos.
    expect(rels, contains('relationships/drawing'));
    expect(
      RegExp('Id="rId1"').allMatches(rels).length,
      1,
      reason: 'un id repetido deja el archivo inconsistente',
    );
  });

  test('las partes escritas a mano son UTF-8 válido', () {
    // La prueba que faltaba, y por eso el archivo llego roto a Excel.
    //
    // La primera version escribia con `.codeUnits`, que son unidades UTF-16 y
    // no bytes: la "é" de "Teléfono" salio como el byte suelto 0xE9 en vez de
    // los dos bytes que UTF-8 necesita. Excel rechazo el libro entero y
    // ofrecio repararlo. Nada del lado de Dart se quejo, y las pruebas
    // pasaban porque todos sus encabezados eran ASCII puro — mientras el
    // reporte real trae "Teléfono", "Última tarea" y "Racha máxima".
    final r = construir();
    for (final parte in [
      'xl/tables/table1.xml',
      'xl/tables/table2.xml',
      '[Content_Types].xml',
      'xl/worksheets/sheet1.xml',
      'xl/worksheets/_rels/sheet1.xml.rels',
      'xl/worksheets/_rels/sheet2.xml.rels',
    ]) {
      final bytes =
          r.zip.files.firstWhere((f) => f.name == parte).content as List<int>;
      expect(
        () => utf8.decode(bytes),
        returnsNormally,
        reason: '$parte no es UTF-8 válido; Excel se niega a abrir el libro',
      );
    }
  });

  test('el archivo sigue siendo un xlsx legible después de la cirugía', () {
    final r = construir();
    final leido = Excel.decodeBytes(r.bytes);
    expect(leido.tables.keys, containsAll(['Tareas', 'Clientes']));
    expect(
      leido.tables['Tareas']!.rows[1][1]?.value.toString(),
      'Panadería los andes',
    );
    expect(
      leido.tables['Tareas']!.rows[0][1]?.value.toString(),
      'Teléfono',
      reason: 'el encabezado con tilde tiene que sobrevivir intacto',
    );
  });
}
