import 'package:flutter/material.dart';

/// El recorrido de un requerimiento, de principio a fin.
///
/// En la hoja de cálculo esto vivía en dos columnas —"Aprobación" (Stand By /
/// Aprobado) y "Estado" (No Iniciada / En Desarrollo)— pero no son dos ejes
/// independientes: de las 48 filas, ninguna estaba en "Stand By + En
/// Desarrollo". Nadie desarrolla sin aprobar, así que es una sola secuencia y
/// una sola columna, que además se puede ver como tablero.
///
/// Y es más larga que la de la hoja a propósito. Allí el recorrido se acababa
/// en "En Desarrollo": no había forma de decir *entregado*, *publicado* ni
/// *rechazado*. Por eso las cinco últimas columnas —Entregado a QA,
/// Actualizaciones de QA, Comunicado al cliente— estaban vacías en las 48
/// filas: no era que no pasara, era que no había dónde anotarlo.
abstract final class RequirementStatus {
  static const String recibido = 'Recibido';
  static const String aprobado = 'Aprobado';
  static const String enDesarrollo = 'En desarrollo';
  static const String enQa = 'En QA';
  static const String publicado = 'Publicado';
  static const String comunicado = 'Comunicado al cliente';

  /// Salidas laterales. "En pausa" es el "Stand By" de la hoja; "Rechazado"
  /// no existía y hacía falta: un requerimiento que no se va a hacer se
  /// quedaba en Stand By para siempre, igual que uno que sí.
  static const String enPausa = 'En pausa';
  static const String rechazado = 'Rechazado';

  /// El camino principal, en orden. Es el que dibuja el tablero.
  static const List<String> flujo = [
    recibido,
    aprobado,
    enDesarrollo,
    enQa,
    publicado,
    comunicado,
  ];

  static const List<String> all = [...flujo, enPausa, rechazado];

  /// Los que siguen vivos: ni entregados al cliente ni descartados.
  static const List<String> openStates = [
    recibido,
    aprobado,
    enDesarrollo,
    enQa,
    publicado,
  ];

  static bool isOpen(String status) => openStates.contains(status);

  /// Si ya salió del área de soporte y está en manos del equipo técnico.
  static bool enManosDeDesarrollo(String status) =>
      status == enDesarrollo || status == enQa;

  static const Map<String, Color> colors = {
    recibido: Colors.blueGrey,
    aprobado: Colors.blue,
    enDesarrollo: Colors.purple,
    enQa: Colors.orange,
    publicado: Colors.teal,
    comunicado: Colors.green,
    enPausa: Colors.amber,
    rechazado: Colors.red,
  };

  static Color colorFor(String status) => colors[status] ?? Colors.grey;
}

/// Qué clase de requerimiento es. Los tres valores son los de la hoja.
///
/// "Bugs" aparece una sola vez en 48 filas, y es correcto que así sea: un
/// fallo se registra en Casos de Soporte. Aquí sólo llega el que termina
/// siendo un cambio al producto.
abstract final class RequirementType {
  static const String mejoras = 'Mejoras';
  static const String solicitudes = 'Solicitudes';
  static const String bugs = 'Bugs';

  static const List<String> all = [mejoras, solicitudes, bugs];

  static const Map<String, Color> colors = {
    mejoras: Colors.indigo,
    solicitudes: Colors.teal,
    bugs: Colors.red,
  };

  static Color colorFor(String type) => colors[type] ?? Colors.grey;
}

/// De dónde salió: lo pidió un cliente o salió de adentro.
abstract final class RequirementOrigin {
  static const String cliente = 'Requerimiento de Clientes';
  static const String interno = 'Requerimiento Interno';

  static const List<String> all = [cliente, interno];
}

/// Quién lo recibió. Son las áreas de la hoja.
abstract final class RequirementSource {
  static const List<String> all = [
    'Soporte',
    'Fidelización',
    'Comercial',
    'Dirección',
  ];
}

/// El módulo de VinApp al que afecta.
///
/// La hoja tenía "Facturación Electrónica" y "Facturacion" como dos opciones
/// distintas del mismo desplegable — el mismo módulo escrito de dos formas.
/// Aquí va una sola.
abstract final class RequirementModule {
  /// El cajón de sastre. Tiene nombre propio porque hay que poder ponerlo de
  /// último en la lista y saber cuál es sin compararlo contra una cadena
  /// suelta escrita en tres sitios.
  static const String otros = 'Otros';

  /// Los que venían en la hoja. El equipo puede agregar más desde el
  /// formulario (ver `CatalogProvider.requirementModules`); éstos son la
  /// base que toda empresa tiene desde el primer día.
  static const List<String> all = [
    'Inventario',
    'Productos',
    'Facturación Electrónica',
    'Caja',
    'Reportes',
    'Dashboard',
    'Link de pedidos',
    'Link de meseros',
    'Impresión',
    'Operación general',
    'Órdenes',
    'Usuarios',
    'Domicilios',
    otros,
  ];
}

/// Prioridad, igual que en la hoja.
abstract final class RequirementPriority {
  static const String sinPrioridad = 'Sin prioridad';
  static const String baja = 'Baja';
  static const String media = 'Media';
  static const String alta = 'Alta';

  static const List<String> all = [sinPrioridad, baja, media, alta];

  static const Map<String, Color> colors = {
    sinPrioridad: Colors.grey,
    baja: Colors.green,
    media: Colors.amber,
    alta: Colors.red,
  };

  static Color colorFor(String p) => colors[p] ?? Colors.grey;

  /// Para ordenar de más urgente a menos.
  static int rank(String p) => all.indexOf(p);
}
