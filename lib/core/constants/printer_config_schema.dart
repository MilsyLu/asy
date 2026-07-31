/// Static schema for the "Configuración del VinApp Print" module — describes
/// every field VinApp Print's own (separate, unrelated) desktop settings
/// screens expose, so the CheCu form can be built by looping over this list
/// instead of hand-writing ~88 widgets. Kept in sync by hand with
/// `functions/src/printerConfigSchema.js` (the Cloud Function's mirror, used
/// to build the AI extraction tool's schema) — see that file's header
/// comment.
library;

/// Every "Si/No" toggle in VinApp Print (including the ones that gate an
/// entire section, e.g. "Imprimir Comandas") is modeled as [boolean] here —
/// functionally identical to a 2-option dropdown, and it keeps this enum to
/// 4 cases instead of 5.
enum PrinterConfigFieldType { text, number, boolean, dropdown }

/// Section keys — group the form UI (one header + field group per section)
/// and prefix every field key below (`<section>_<campo>`).
class PrinterConfigSections {
  PrinterConfigSections._();

  static const String general = 'general';
  static const String comandas = 'comandas';
  static const String facturas = 'facturas';
  static const String bebidas = 'bebidas';
  static const String domicilio = 'domicilio';
  static const String cuenta = 'cuenta';
  static const String licencia = 'licencia';

  static const List<String> all = [
    general,
    comandas,
    facturas,
    bebidas,
    domicilio,
    cuenta,
    licencia,
  ];

  static const Map<String, String> labels = {
    general: 'Configuración de impresión (general)',
    comandas: 'Comandas',
    facturas: 'Facturas',
    bebidas: 'Bebidas',
    domicilio: 'Domicilio',
    cuenta: 'Cuenta',
    licencia: 'Licencia y punto',
  };
}

class PrinterConfigFieldSchema {
  const PrinterConfigFieldSchema({
    required this.key,
    required this.label,
    required this.section,
    required this.type,
    this.dropdownOptions = const [],
    this.placeholder,
    this.defaultValue,
    this.compact = false,
  });

  /// Unique across the whole schema — also the key stored in
  /// [PrinterConfigModel.fields] and the JSON property name sent to/from
  /// Claude's extraction tool (see `functions/src/printerConfigSchema.js`).
  final String key;
  final String label;

  /// One of [PrinterConfigSections].
  final String section;
  final PrinterConfigFieldType type;

  /// Only meaningful when [type] is [PrinterConfigFieldType.dropdown].
  final List<String> dropdownOptions;
  final String? placeholder;

  /// Pre-filled when creating a NEW ficha (never applied when editing an
  /// existing one, which always shows its own saved values) — Michel's
  /// "configuración básica" that most installations start from. `null` for
  /// fields with no known common default (printer names, licencia/punto,
  /// free-text content fields). See [PrinterConfigSchema.defaultValues].
  final dynamic defaultValue;

  /// True for short-content fields (numbers, "Normal", "Comanda"...) that
  /// don't need a full grid column — rendered at half width so more fit per
  /// row. Only set on the "Configuración de impresión (general)" fields
  /// whose values are always short; the 7 printer-name fields in that same
  /// section stay full width since a printer name can be long.
  final bool compact;
}

/// 85 fields total, one per real VinApp Print setting (confirmed against
/// actual screenshots, not guessed) — 18 general + 15 comandas +
/// 22 facturas + 10 bebidas + 5 domicilio + 13 cuenta + 2 licencia.
///
/// KEEP IN SYNC WITH `functions/src/printerConfigSchema.js` — every key
/// added/removed here must be mirrored there, or the AI extraction tool's
/// schema will drift from what the form actually renders.
class PrinterConfigSchema {
  PrinterConfigSchema._();

  static const List<PrinterConfigFieldSchema> fields = [
    // ---- general (19) -------------------------------------------------
    PrinterConfigFieldSchema(key: 'general_impresoraComandas1', label: 'Impresora de comandas 1', section: PrinterConfigSections.general, type: PrinterConfigFieldType.text),
    PrinterConfigFieldSchema(key: 'general_impresoraComandas2', label: 'Impresora de comandas 2', section: PrinterConfigSections.general, type: PrinterConfigFieldType.text),
    PrinterConfigFieldSchema(key: 'general_impresoraComandas3', label: 'Impresora de comandas 3', section: PrinterConfigSections.general, type: PrinterConfigFieldType.text),
    PrinterConfigFieldSchema(key: 'general_impresoraFacturas', label: 'Impresora de facturas', section: PrinterConfigSections.general, type: PrinterConfigFieldType.text),
    PrinterConfigFieldSchema(key: 'general_impresoraDomicilio', label: 'Impresora de domicilio', section: PrinterConfigSections.general, type: PrinterConfigFieldType.text),
    PrinterConfigFieldSchema(key: 'general_impresoraCuenta', label: 'Impresora de cuenta', section: PrinterConfigSections.general, type: PrinterConfigFieldType.text),
    PrinterConfigFieldSchema(key: 'general_impresoraBebidas', label: 'Impresora de bebidas', section: PrinterConfigSections.general, type: PrinterConfigFieldType.text),
    PrinterConfigFieldSchema(key: 'general_corteAutomatico', label: 'Corte automático', section: PrinterConfigSections.general, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'general_tipoPapel', label: 'Tipo de papel', section: PrinterConfigSections.general, type: PrinterConfigFieldType.dropdown, dropdownOptions: ['Normal', 'Pequeño'], defaultValue: 'Normal', compact: true),
    PrinterConfigFieldSchema(key: 'general_anchoPapel', label: 'Ancho de papel', section: PrinterConfigSections.general, type: PrinterConfigFieldType.number, defaultValue: 280, compact: true),
    PrinterConfigFieldSchema(key: 'general_anchoPapelComanda', label: 'Ancho de papel comanda', section: PrinterConfigSections.general, type: PrinterConfigFieldType.number, defaultValue: 280, compact: true),
    PrinterConfigFieldSchema(key: 'general_tamanoFuente', label: 'Tamaño de fuente', section: PrinterConfigSections.general, type: PrinterConfigFieldType.number, defaultValue: 12, compact: true),
    PrinterConfigFieldSchema(key: 'general_primeraImpresion', label: 'Primera impresión', section: PrinterConfigSections.general, type: PrinterConfigFieldType.text, defaultValue: 'Comanda', compact: true),
    PrinterConfigFieldSchema(key: 'general_espaciadoAltoLogo', label: 'Espaciado alto para el logo', section: PrinterConfigSections.general, type: PrinterConfigFieldType.number, defaultValue: 0, compact: true),
    PrinterConfigFieldSchema(key: 'general_espaciadoIzquierdaLogo', label: 'Espaciado izquierda para el logo', section: PrinterConfigSections.general, type: PrinterConfigFieldType.number, defaultValue: 40, compact: true),
    PrinterConfigFieldSchema(key: 'general_espaciadoDebajoInfoEmpresa', label: 'Espaciado debajo de info de empresa', section: PrinterConfigSections.general, type: PrinterConfigFieldType.number, defaultValue: 45, compact: true),
    PrinterConfigFieldSchema(key: 'general_espaciadoDebajoTextoFinal', label: 'Espaciado debajo del texto final', section: PrinterConfigSections.general, type: PrinterConfigFieldType.number, defaultValue: 45, compact: true),
    PrinterConfigFieldSchema(key: 'general_espaciadoAltoComanda', label: 'Espaciado alto para la comanda', section: PrinterConfigSections.general, type: PrinterConfigFieldType.number, defaultValue: 0, compact: true),

    // ---- comandas (15) --------------------------------------------------
    PrinterConfigFieldSchema(key: 'comandas_imprimirComandas', label: 'Imprimir Comandas', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_totalOrden', label: 'Total Orden', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_nombreCliente', label: 'Nombre Cliente', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_direccionCliente', label: 'Dirección Cliente', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_telefonoCliente', label: 'Teléfono Cliente', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_formaPago', label: 'Forma de Pago', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'comandas_bebidas', label: 'Bebidas', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_observacionesAdicionales', label: 'Observaciones Adicionales', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_nombreEmpresa', label: 'Nombre Empresa', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_textoAdicional', label: 'Texto Adicional', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'comandas_textoAdicionalValor', label: 'Texto adicional (contenido)', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.text, placeholder: 'Null'),
    PrinterConfigFieldSchema(key: 'comandas_imprimirTodas', label: 'Imprimir todas', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_imprimirDesdeApp', label: 'Imprimir desde App', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'comandas_agruparPorCategoria', label: 'Agrupar por categoría', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'comandas_imprimirComandasNegativas', label: 'Imprimir Comandas Negativas', section: PrinterConfigSections.comandas, type: PrinterConfigFieldType.boolean),

    // ---- facturas (22) ----------------------------------------------------
    PrinterConfigFieldSchema(key: 'facturas_imprimirFacturas', label: 'Imprimir Facturas', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_logo', label: 'Logo', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_infRest', label: 'Inf. Rest.', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_textoInicio', label: 'Texto Inicio', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'facturas_textoInicioValor', label: 'Texto Inicio (contenido)', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.text, placeholder: 'Null'),
    PrinterConfigFieldSchema(key: 'facturas_textoInicioConFE', label: 'Texto Inicio con FE', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'facturas_textoInicioConFEValor', label: 'Texto Inicio con FE (contenido)', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.text, placeholder: 'Null'),
    PrinterConfigFieldSchema(key: 'facturas_fechaEntrega', label: 'Fecha de Entrega', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_vendedor', label: 'Vendedor', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_mesero', label: 'Mesero', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_cedula', label: 'Cédula', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_mesa', label: 'Mesa', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_barrio', label: 'Barrio', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_infFactura', label: 'Inf. Factura', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_mensajero', label: 'Mensajero', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_todas', label: 'Todas', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_observaciones', label: 'Observaciones', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_qr', label: 'QR', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_textoFinal', label: 'Texto Final', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'facturas_textoFinalValor', label: 'Texto Final (contenido)', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.text, placeholder: 'Null'),
    PrinterConfigFieldSchema(key: 'facturas_textoPorDefecto', label: 'Texto Por Defecto', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'facturas_valorRappi', label: 'Valor Rappi', section: PrinterConfigSections.facturas, type: PrinterConfigFieldType.boolean, defaultValue: true),

    // ---- bebidas (10) -------------------------------------------------------
    PrinterConfigFieldSchema(key: 'bebidas_imprimirBebidas', label: 'Imprimir Bebidas', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean, defaultValue: false),
    PrinterConfigFieldSchema(key: 'bebidas_nombreCliente', label: 'Nombre Cliente', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'bebidas_direccionCliente', label: 'Dirección Cliente', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'bebidas_observacionesAdicionales', label: 'Observaciones Adicionales', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'bebidas_nombreEmpresa', label: 'Nombre Empresa', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'bebidas_textoAdicional', label: 'Texto Adicional', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'bebidas_textoAdicionalValor', label: 'Texto adicional (contenido)', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.text, placeholder: 'Null'),
    PrinterConfigFieldSchema(key: 'bebidas_imprimirTodas', label: 'Imprimir todas', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'bebidas_imprimirDesdeApp', label: 'Imprimir desde App', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'bebidas_imprimirBebidasNegativas', label: 'Imprimir Bebidas Negativas', section: PrinterConfigSections.bebidas, type: PrinterConfigFieldType.boolean, defaultValue: false),

    // ---- domicilio (5, excluye "cuenta" anidado — ver sección propia) -------
    PrinterConfigFieldSchema(key: 'domicilio_imprimirDomicilio', label: 'Imprimir Domicilio', section: PrinterConfigSections.domicilio, type: PrinterConfigFieldType.boolean, defaultValue: false),
    PrinterConfigFieldSchema(key: 'domicilio_fechaEntrega', label: 'Fecha Entrega', section: PrinterConfigSections.domicilio, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'domicilio_vendedor', label: 'Vendedor', section: PrinterConfigSections.domicilio, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'domicilio_observacionesAdicionales', label: 'Observaciones Adicionales', section: PrinterConfigSections.domicilio, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'domicilio_imprimirCuentas', label: 'Imprimir Cuentas', section: PrinterConfigSections.domicilio, type: PrinterConfigFieldType.boolean, defaultValue: true),

    // ---- cuenta (13, "Información Cuenta" anidada bajo Domicilio) -----------
    PrinterConfigFieldSchema(key: 'cuenta_logo', label: 'Logo', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_infRest', label: 'Inf. Rest.', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_textoInicio', label: 'Texto Inicio', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean),
    PrinterConfigFieldSchema(key: 'cuenta_textoInicioValor', label: 'Texto Inicio (contenido)', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.text, placeholder: 'Null'),
    PrinterConfigFieldSchema(key: 'cuenta_fechaEntrega', label: 'Fecha de Entrega', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_vendedor', label: 'Vendedor', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_mesero', label: 'Mesero', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_cedulaCliente', label: 'Cédula Cliente', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_barrio', label: 'Barrio', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_mesa', label: 'Mesa', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_infCuenta', label: 'Inf. Cuenta', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_imprimirTodas', label: 'Imprimir todas', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),
    PrinterConfigFieldSchema(key: 'cuenta_imprimirDesdeApp', label: 'Imprimir desde App', section: PrinterConfigSections.cuenta, type: PrinterConfigFieldType.boolean, defaultValue: true),

    // ---- licencia (4) ---------------------------------------------------------
    PrinterConfigFieldSchema(key: 'licencia_licencia', label: 'Licencia', section: PrinterConfigSections.licencia, type: PrinterConfigFieldType.text),
    PrinterConfigFieldSchema(key: 'licencia_punto', label: 'Punto', section: PrinterConfigSections.licencia, type: PrinterConfigFieldType.text),
  ];

  /// Fields belonging to [section], in declared order.
  static List<PrinterConfigFieldSchema> forSection(String section) =>
      fields.where((f) => f.section == section).toList();

  /// "Configuración básica" — the values a NEW ficha starts pre-filled
  /// with, taken from [PrinterConfigFieldSchema.defaultValue]. Never
  /// applied when editing an existing ficha (see `_PrinterConfigFormPage`).
  static Map<String, dynamic> get defaultValues => {
        for (final f in fields)
          if (f.defaultValue != null) f.key: f.defaultValue,
      };
}
