/**
 * KEEP IN SYNC WITH lib/core/constants/printer_config_schema.dart — 88
 * entries, one per real VinApp Print setting (confirmed against actual
 * screenshots). Used to build the `input_schema` for the Claude tool-use
 * call in extractPrinterConfigFromImages.js, so the AI's extraction and the
 * Flutter form always agree on field keys. Only changes when VinApp Print's
 * own settings screens change (rare) — this file and the Dart one are
 * maintained by hand, not generated from a single source; a length check on
 * both sides (see extractPrinterConfigFromImages.js's smoke test) catches
 * the most common drift (a field added on one side and forgotten on the
 * other).
 */
const PRINTER_CONFIG_FIELDS = [
  // ---- general (19) --------------------------------------------------
  { key: "general_impresoraComandas1", label: "Impresora de comandas 1", type: "text" },
  { key: "general_impresoraComandas2", label: "Impresora de comandas 2", type: "text" },
  { key: "general_impresoraComandas3", label: "Impresora de comandas 3", type: "text" },
  { key: "general_impresoraFacturas", label: "Impresora de facturas", type: "text" },
  { key: "general_impresoraDomicilio", label: "Impresora de domicilio", type: "text" },
  { key: "general_impresoraCuenta", label: "Impresora de cuenta", type: "text" },
  { key: "general_impresoraBebidas", label: "Impresora de bebidas", type: "text" },
  { key: "general_corteAutomatico", label: "Corte automático", type: "boolean" },
  { key: "general_tipoPapel", label: "Tipo de papel", type: "text" },
  { key: "general_anchoPapel", label: "Ancho de papel", type: "number" },
  { key: "general_anchoPapelComanda", label: "Ancho de papel comanda", type: "number" },
  { key: "general_tamanoFuente", label: "Tamaño de fuente", type: "number" },
  { key: "general_espaciadoAltoLogo", label: "Espaciado alto para el logo", type: "number" },
  { key: "general_espaciadoIzquierdaLogo", label: "Espaciado izquierda para el logo", type: "number" },
  { key: "general_espaciadoDebajoTextoFinal", label: "Espaciado debajo del texto final", type: "number" },
  { key: "general_primeraImpresion", label: "Primera impresión", type: "text" },
  { key: "general_espaciadoAltoComanda", label: "Espaciado alto para la comanda", type: "number" },
  { key: "general_espaciadoDebajoInfoEmpresa", label: "Espaciado debajo de info de empresa", type: "number" },

  // ---- comandas (15) ---------------------------------------------------
  { key: "comandas_imprimirComandas", label: "Imprimir Comandas", type: "boolean" },
  { key: "comandas_totalOrden", label: "Total Orden", type: "boolean" },
  { key: "comandas_nombreCliente", label: "Nombre Cliente", type: "boolean" },
  { key: "comandas_direccionCliente", label: "Dirección Cliente", type: "boolean" },
  { key: "comandas_telefonoCliente", label: "Teléfono Cliente", type: "boolean" },
  { key: "comandas_formaPago", label: "Forma de Pago", type: "boolean" },
  { key: "comandas_bebidas", label: "Bebidas", type: "boolean" },
  { key: "comandas_observacionesAdicionales", label: "Observaciones Adicionales", type: "boolean" },
  { key: "comandas_nombreEmpresa", label: "Nombre Empresa", type: "boolean" },
  { key: "comandas_textoAdicional", label: "Texto Adicional", type: "boolean" },
  { key: "comandas_textoAdicionalValor", label: "Texto adicional (contenido)", type: "text" },
  { key: "comandas_imprimirTodas", label: "Imprimir todas", type: "boolean" },
  { key: "comandas_imprimirDesdeApp", label: "Imprimir desde App", type: "boolean" },
  { key: "comandas_agruparPorCategoria", label: "Agrupar por categoría", type: "boolean" },
  { key: "comandas_imprimirComandasNegativas", label: "Imprimir Comandas Negativas", type: "boolean" },

  // ---- facturas (22) -------------------------------------------------------
  { key: "facturas_imprimirFacturas", label: "Imprimir Facturas", type: "boolean" },
  { key: "facturas_logo", label: "Logo", type: "boolean" },
  { key: "facturas_infRest", label: "Inf. Rest.", type: "boolean" },
  { key: "facturas_textoInicio", label: "Texto Inicio", type: "boolean" },
  { key: "facturas_textoInicioValor", label: "Texto Inicio (contenido)", type: "text" },
  { key: "facturas_textoInicioConFE", label: "Texto Inicio con FE", type: "boolean" },
  { key: "facturas_textoInicioConFEValor", label: "Texto Inicio con FE (contenido)", type: "text" },
  { key: "facturas_fechaEntrega", label: "Fecha de Entrega", type: "boolean" },
  { key: "facturas_vendedor", label: "Vendedor", type: "boolean" },
  { key: "facturas_mesero", label: "Mesero", type: "boolean" },
  { key: "facturas_cedula", label: "Cédula", type: "boolean" },
  { key: "facturas_mesa", label: "Mesa", type: "boolean" },
  { key: "facturas_barrio", label: "Barrio", type: "boolean" },
  { key: "facturas_infFactura", label: "Inf. Factura", type: "boolean" },
  { key: "facturas_mensajero", label: "Mensajero", type: "boolean" },
  { key: "facturas_todas", label: "Todas", type: "boolean" },
  { key: "facturas_observaciones", label: "Observaciones", type: "boolean" },
  { key: "facturas_qr", label: "QR", type: "boolean" },
  { key: "facturas_textoFinal", label: "Texto Final", type: "boolean" },
  { key: "facturas_textoFinalValor", label: "Texto Final (contenido)", type: "text" },
  { key: "facturas_textoPorDefecto", label: "Texto Por Defecto", type: "boolean" },
  { key: "facturas_valorRappi", label: "Valor Rappi", type: "boolean" },

  // ---- bebidas (10) ----------------------------------------------------------
  { key: "bebidas_imprimirBebidas", label: "Imprimir Bebidas", type: "boolean" },
  { key: "bebidas_nombreCliente", label: "Nombre Cliente", type: "boolean" },
  { key: "bebidas_direccionCliente", label: "Dirección Cliente", type: "boolean" },
  { key: "bebidas_observacionesAdicionales", label: "Observaciones Adicionales", type: "boolean" },
  { key: "bebidas_nombreEmpresa", label: "Nombre Empresa", type: "boolean" },
  { key: "bebidas_textoAdicional", label: "Texto Adicional", type: "boolean" },
  { key: "bebidas_textoAdicionalValor", label: "Texto adicional (contenido)", type: "text" },
  { key: "bebidas_imprimirTodas", label: "Imprimir todas", type: "boolean" },
  { key: "bebidas_imprimirDesdeApp", label: "Imprimir desde App", type: "boolean" },
  { key: "bebidas_imprimirBebidasNegativas", label: "Imprimir Bebidas Negativas", type: "boolean" },

  // ---- domicilio (5) -----------------------------------------------------------
  { key: "domicilio_imprimirDomicilio", label: "Imprimir Domicilio", type: "boolean" },
  { key: "domicilio_fechaEntrega", label: "Fecha Entrega", type: "boolean" },
  { key: "domicilio_vendedor", label: "Vendedor", type: "boolean" },
  { key: "domicilio_observacionesAdicionales", label: "Observaciones Adicionales", type: "boolean" },
  { key: "domicilio_imprimirCuentas", label: "Imprimir Cuentas", type: "boolean" },

  // ---- cuenta (13, "Información Cuenta" anidada bajo Domicilio) -----------------
  { key: "cuenta_logo", label: "Logo", type: "boolean" },
  { key: "cuenta_infRest", label: "Inf. Rest.", type: "boolean" },
  { key: "cuenta_textoInicio", label: "Texto Inicio", type: "boolean" },
  { key: "cuenta_textoInicioValor", label: "Texto Inicio (contenido)", type: "text" },
  { key: "cuenta_fechaEntrega", label: "Fecha de Entrega", type: "boolean" },
  { key: "cuenta_vendedor", label: "Vendedor", type: "boolean" },
  { key: "cuenta_mesero", label: "Mesero", type: "boolean" },
  { key: "cuenta_cedulaCliente", label: "Cédula Cliente", type: "boolean" },
  { key: "cuenta_barrio", label: "Barrio", type: "boolean" },
  { key: "cuenta_mesa", label: "Mesa", type: "boolean" },
  { key: "cuenta_infCuenta", label: "Inf. Cuenta", type: "boolean" },
  { key: "cuenta_imprimirTodas", label: "Imprimir todas", type: "boolean" },
  { key: "cuenta_imprimirDesdeApp", label: "Imprimir desde App", type: "boolean" },

  // ---- licencia (4) ---------------------------------------------------------------
  { key: "licencia_licencia", label: "Licencia", type: "text" },
  { key: "licencia_punto", label: "Punto", type: "text" },
];

/** Builds the Anthropic tool `input_schema.properties` object from the field list. */
function buildToolProperties() {
  const properties = {};
  for (const f of PRINTER_CONFIG_FIELDS) {
    if (f.type === "boolean") properties[f.key] = { type: "boolean", description: f.label };
    else if (f.type === "number") properties[f.key] = { type: "number", description: f.label };
    else properties[f.key] = { type: "string", description: f.label };
  }
  return properties;
}

module.exports = { PRINTER_CONFIG_FIELDS, buildToolProperties };
