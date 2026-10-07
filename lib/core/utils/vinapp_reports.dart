import 'package:excel/excel.dart';

import 'excel_export.dart' show excelBytes, headerStyle;
import 'excel_tables.dart';
import 'report_filters.dart' show foldAccents;

/// Los listados que VinApp publica como Excel y que CheCu vuelve a entregar
/// con un formato usable.
///
/// Todos salen de `alfa.vinapp.co`. El de clientes también existe en `beta`,
/// pero mezclar ambientes daría datos de uno u otro sin que nada lo anuncie,
/// así que hay un solo origen y está aquí, en un sitio.
enum VinAppReport {
  clientes(
    ruta: 'export-clients-history',
    titulo: 'Clientes',
    descripcion: 'Historial de clientes de la licencia',
    hoja: 'Clientes',
    archivo: 'Clientes',
  ),
  recetas(
    ruta: 'export-recipes',
    titulo: 'Recetas',
    descripcion: 'Recetas y subrecetas con sus ingredientes',
    hoja: 'Recetas',
    archivo: 'Recetas',
  ),
  adiciones(
    ruta: 'export-additions',
    titulo: 'Adiciones',
    descripcion: 'Grupos de adición por producto',
    hoja: 'Adiciones',
    archivo: 'Adiciones',
  );

  const VinAppReport({
    required this.ruta,
    required this.titulo,
    required this.descripcion,
    required this.hoja,
    required this.archivo,
  });

  /// Último tramo de la URL, antes del id de licencia.
  final String ruta;

  /// Nombre en pantalla.
  final String titulo;

  /// Qué trae, en una línea.
  final String descripcion;

  /// Nombre de la hoja dentro del Excel. El original la llama "Worksheet".
  final String hoja;

  /// Parte fija del nombre del archivo.
  final String archivo;

  static const String base = 'https://alfa.vinapp.co/api/report';

  String urlPara(String licencia) => '$base/$ruta/${licencia.trim()}';

  String nombreArchivo(String licencia, DateTime cuando) {
    final f = '${cuando.year}-${_dos(cuando.month)}-${_dos(cuando.day)}';
    return 'VinApp_${archivo}_${licencia.trim()}_$f.xlsx';
  }
}

String _dos(int n) => n.toString().padLeft(2, '0');

/// Cómo se escribe una columna, decidido por el texto de su encabezado.
///
/// Público porque lo devuelve [formatoDeColumna], que es la regla que las
/// pruebas comprueban: es más barato verificar "TELÉFONO va como texto" que
/// abrir el .xlsx resultante y buscar el formato de la celda.
enum FormatoColumna {
  /// Lo que traiga el origen, tal cual.
  comoVenga,

  /// Forzado a texto. Un teléfono guardado como número pierde los ceros de la
  /// izquierda y, si es largo, Excel lo muestra como 3,21886E+09.
  texto,

  /// Pesos, sin decimales.
  dinero,

  /// Con dos decimales: cantidades de receta como 0,262.
  decimal,
}

/// El formato que le toca a una columna según su encabezado.
///
/// Por nombre y no por posición a propósito: si VinApp agrega o mueve una
/// columna, esto sigue acertando en las que conoce y deja las demás como
/// vengan, en vez de aplicarle el formato de "COSTO" a lo que ahora esté en
/// esa posición. Compara sin tildes porque los encabezados llegan como
/// "CATEGORÍA" y "TELÉFONO".
FormatoColumna formatoDeColumna(String encabezado) {
  final h = foldAccents(encabezado);
  if (h.contains('telefono') ||
      h.contains('celular') ||
      h.contains('cedula') ||
      h.contains('identificacion') ||
      h.contains('nit')) {
    return FormatoColumna.texto;
  }
  if (h.contains('costo') || h.contains('valor') || h.contains('precio')) {
    return FormatoColumna.dinero;
  }
  if (h.contains('cantidad')) return FormatoColumna.decimal;
  return FormatoColumna.comoVenga;
}

/// Ancho de la columna, también por el nombre del encabezado.
///
/// El original deja las 8 columnas en 13, así que una dirección completa se ve
/// cortada y "EMAIL" sobra espacio. Son los anchos que hacen que el archivo se
/// pueda leer sin tocar nada al abrirlo.
double anchoDeColumna(String encabezado) {
  final h = foldAccents(encabezado);
  if (h.contains('direccion')) return 42;
  if (h.contains('nombre') || h.contains('email')) return 32;
  if (h.contains('ingrediente') || h.contains('producto')) return 30;
  if (h.contains('barrio') ||
      h.contains('adicion') ||
      h.contains('categoria')) {
    return 26;
  }
  if (h.contains('observacion') || h.contains('comentario')) return 40;
  return 16;
}

/// Reescribe el Excel que entrega VinApp con un formato usable.
///
/// Lo que llega es una tabla cruda: la hoja se llama "Worksheet", el
/// encabezado no se distingue del resto, las ocho columnas miden lo mismo y
/// no hay filtros. Esto lo devuelve con encabezado fijo y filtrable, anchos
/// reales, los teléfonos como texto y los costos como pesos.
///
/// Función libre y sin red para que se pueda probar de verdad: recibe los
/// bytes y devuelve bytes. Quién los trajo es problema de otro.
///
/// Los encabezados y el orden de las columnas salen del archivo recibido, no
/// de una lista escrita aquí. Si VinApp agrega una columna, aparece; si la
/// quita, desaparece. Una lista propia se quedaría vieja en silencio, que es
/// la forma favorita que tiene este proyecto de romperse.
/// Devuelve los bytes y cuántas filas de datos quedaron. El conteo sale de
/// aquí y no de volver a abrir el archivo: el de clientes pesa 288 KB y
/// decodificarlo otra vez sólo para contar filas es trabajo repetido.
({List<int> bytes, int registros}) reformatVinAppWorkbook({
  required List<int> sourceBytes,
  required VinAppReport report,
  required String licencia,
  required DateTime generadoEl,
}) {
  final origen = Excel.decodeBytes(sourceBytes);
  final primera = origen.tables.keys.first;
  final filas = origen.tables[primera]!.rows;

  final encabezados = <String>[];
  if (filas.isNotEmpty) {
    for (final celda in filas.first) {
      final texto = celda?.value?.toString().trim() ?? '';
      // Un encabezado vacío o repetido hace que Excel rechace la tabla
      // entera, así que la columna se nombra en vez de dejarla romper el
      // archivo.
      final nombre = texto.isEmpty
          ? 'Columna ${encabezados.length + 1}'
          : texto;
      encabezados.add(
        encabezados.contains(nombre)
            ? '$nombre (${encabezados.length + 1})'
            : nombre,
      );
    }
  }

  final destino = Excel.createExcel();
  final hoja = destino[report.hoja];
  destino.setDefaultSheet(report.hoja);
  for (final nombre in destino.tables.keys.toList()) {
    if (nombre != report.hoja) destino.delete(nombre);
  }

  if (encabezados.isEmpty) {
    return (bytes: excelBytes(destino), registros: 0);
  }

  final formatos = [for (final h in encabezados) formatoDeColumna(h)];

  hoja.appendRow([for (final h in encabezados) TextCellValue(h)]);
  for (var c = 0; c < encabezados.length; c++) {
    hoja
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .cellStyle =
        headerStyle;
    hoja.setColumnWidth(c, anchoDeColumna(encabezados[c]));
  }

  var escritas = 0;
  for (var f = 1; f < filas.length; f++) {
    final fila = filas[f];
    final valores = <CellValue?>[];
    for (var c = 0; c < encabezados.length; c++) {
      final origenCelda = c < fila.length ? fila[c]?.value : null;
      valores.add(_convertir(origenCelda, formatos[c]));
    }
    // Una fila entera vacía al final del original agregaría una fila en blanco
    // dentro de la tabla, y ahí el filtro empieza a contar vacíos como datos.
    if (valores.every((v) => v == null)) continue;

    hoja.appendRow(valores);
    escritas++;
    final r = escritas;
    for (var c = 0; c < encabezados.length; c++) {
      final estilo = _estiloDe(formatos[c]);
      if (estilo == null) continue;
      hoja
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
              .cellStyle =
          estilo;
    }
  }

  _hojaDeInformacion(
    destino,
    report: report,
    licencia: licencia,
    generadoEl: generadoEl,
    columnas: encabezados.length,
    registros: escritas,
  );

  final bytes = excelBytes(destino);

  // El encabezado fijo y los filtros no los sabe hacer el paquete `excel`;
  // esto los escribe dentro del .xlsx. La tabla siempre arranca en A1, por eso
  // los datos van solos en su hoja y la ficha de la descarga va en otra.
  return (
    bytes: addExcelTables(bytes, [
      TableSpec(sheet: report.hoja, headers: encabezados, dataRows: escritas),
    ]),
    registros: escritas,
  );
}

CellValue? _convertir(CellValue? origen, FormatoColumna formato) {
  if (origen == null) return null;

  switch (formato) {
    case FormatoColumna.texto:
      final texto = switch (origen) {
        IntCellValue(:final value) => value.toString(),
        DoubleCellValue(:final value) =>
          value == value.roundToDouble()
              ? value.toInt().toString()
              : value.toString(),
        _ => origen.toString(),
      };
      return texto.trim().isEmpty ? null : TextCellValue(texto.trim());

    case FormatoColumna.dinero:
    case FormatoColumna.decimal:
      return switch (origen) {
        IntCellValue(:final value) => IntCellValue(value),
        DoubleCellValue(:final value) => DoubleCellValue(value),
        // Un número que llegó como texto se queda como texto: convertirlo a
        // ciegas convierte "N/A" o "1.200,50" en basura o en cero.
        _ => _texto(origen),
      };

    case FormatoColumna.comoVenga:
      return origen is TextCellValue ? _texto(origen) : origen;
  }
}

CellValue? _texto(CellValue origen) {
  final t = origen.toString().trim();
  return t.isEmpty ? null : TextCellValue(t);
}

CellStyle? _estiloDe(FormatoColumna formato) => switch (formato) {
  FormatoColumna.texto => CellStyle(numberFormat: NumFormat.standard_49),
  FormatoColumna.dinero => CellStyle(
    numberFormat: const CustomNumericNumFormat(formatCode: '"\$" #,##0'),
    horizontalAlign: HorizontalAlign.Right,
  ),
  FormatoColumna.decimal => CellStyle(numberFormat: NumFormat.standard_4),
  FormatoColumna.comoVenga => null,
};

/// Segunda hoja con de dónde salió el archivo.
///
/// No va encima de los datos porque una tabla de Excel tiene que empezar en
/// A1: un título arriba desplazaría el encabezado y la tabla dejaría de
/// cuadrar. Y hace falta — sin ella, dos descargas de licencias distintas son
/// dos archivos idénticos por dentro.
void _hojaDeInformacion(
  Excel destino, {
  required VinAppReport report,
  required String licencia,
  required DateTime generadoEl,
  required int columnas,
  required int registros,
}) {
  final hoja = destino['Información'];
  final datos = <List<String>>[
    ['Reporte', report.titulo],
    ['Licencia', licencia.trim()],
    [
      'Generado',
      '${generadoEl.day}/${_dos(generadoEl.month)}/${generadoEl.year} '
          '${_dos(generadoEl.hour)}:${_dos(generadoEl.minute)}',
    ],
    ['Registros', '$registros'],
    ['Columnas', '$columnas'],
    ['Origen', report.urlPara(licencia)],
    ['Formato', 'CheCu'],
  ];

  for (final par in datos) {
    hoja.appendRow([TextCellValue(par[0]), TextCellValue(par[1])]);
  }
  for (var r = 0; r < datos.length; r++) {
    hoja
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r))
        .cellStyle = CellStyle(
      bold: true,
    );
  }
  hoja.setColumnWidth(0, 16);
  hoja.setColumnWidth(1, 60);
}
