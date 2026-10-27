import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/requirement_constants.dart';

/// Un desarrollador del equipo técnico, al que se le asigna un requerimiento.
///
/// Catálogo propio y no usuarios de CheCu: Andrés, Wilmer y Kelvin no entran a
/// la app — están del otro lado, en el equipo que construye VinApp. Tratarlos
/// como usuarios obligaría a crearles cuenta para poder nombrarlos.
class DeveloperModel {
  const DeveloperModel({
    required this.id,
    required this.name,
    this.isActive = true,
    this.empresaId,
  });

  final String id;
  final String name;

  /// Entran y salen del equipo. Un inactivo deja de ofrecerse para asignar
  /// nuevos, pero sigue nombrándose en los requerimientos que ya tiene —
  /// borrarlo dejaría esos requerimientos sin responsable.
  final bool isActive;

  final String? empresaId;

  factory DeveloperModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    return DeveloperModel(
      id: doc.id,
      name: m['name'] as String? ?? '',
      isActive: m['isActive'] as bool? ?? true,
      empresaId: m['empresaId'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'isActive': isActive,
    'empresaId': empresaId,
  };
}

/// Un cambio de estado de un requerimiento.
///
/// Es lo que reemplaza a las columnas de fecha de la hoja: "Entregado a QA
/// (fecha)" no es un campo aparte, es el momento en que entró a QA. Un solo
/// registro contesta todas esas preguntas y además dice quién lo movió.
class RequirementEvent {
  const RequirementEvent({
    required this.type,
    required this.text,
    required this.authorId,
    required this.authorName,
    this.createdAt,
  });

  static const String creado = 'created';
  static const String estado = 'status_changed';
  static const String asignado = 'assignee_changed';
  static const String comentario = 'comment';
  static const String notaQa = 'qa_note';
  static const String editado = 'edited';

  final String type;
  final String text;
  final String authorId;
  final String authorName;
  final DateTime? createdAt;

  factory RequirementEvent.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? {};
    return RequirementEvent(
      type: m['type'] as String? ?? comentario,
      text: m['text'] as String? ?? '',
      authorId: m['authorId'] as String? ?? '',
      authorName: m['authorName'] as String? ?? '',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Un requerimiento: algo que un cliente (o el propio equipo) pidió que
/// VinApp hiciera.
///
/// Reemplaza la hoja de cálculo compartida. Los campos que allí casi nunca se
/// llenaban —fecha de recepción en 21 de 48, quién lo recibió en 21 de 48, el
/// número en 12 de 48— aquí los pone la app sola: no hay forma de crear uno
/// sin ellos.
class RequirementModel {
  const RequirementModel({
    required this.id,
    required this.requirementNumber,
    required this.empresaId,
    required this.origin,
    required this.clientIds,
    required this.clientNames,
    required this.type,
    required this.module,
    required this.description,
    required this.status,
    required this.priority,
    this.source = '',
    this.developerId,
    this.developerName = '',
    this.qaNotes = '',
    this.supportCaseId,
    this.supportCaseNumber,
    required this.receivedAt,
    required this.receivedById,
    required this.receivedByName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Correlativo por empresa: REQ-0001. En la hoja era manual y se abandonó
  /// en el 74 — 36 de 48 filas no tenían número.
  final int requirementNumber;

  final String empresaId;

  /// [RequirementOrigin]: lo pidió un cliente o salió de adentro.
  final String origin;

  /// Los clientes que lo pidieron. Lista y no uno solo porque en la hoja hay
  /// filas con dos — "Cecy Dangond, Empanadas donde el mono" — y porque el
  /// mismo requerimiento lo suelen pedir varios.
  final List<String> clientIds;

  /// Los nombres, guardados junto a los ids. Repetirlos permite buscar y
  /// listar sin ir al catálogo por cada fila, y deja legible el requerimiento
  /// de un cliente que después se borró.
  final List<String> clientNames;

  final String type;
  final String module;
  final String description;
  final String status;
  final String priority;

  /// Área que lo recibió ([RequirementSource]).
  final String source;

  /// Desarrollador asignado. Null = sin asignar.
  ///
  /// La hoja tenía además una columna "ASIGNAMIENTO" con ASIGNADO/SIN
  /// ASIGNAR, que es este mismo dato escrito dos veces — y ya se
  /// contradecían: una fila decía ASIGNADO sin responsable. Aquí se deduce.
  final String? developerId;
  final String developerName;

  /// Lo que QA va anotando mientras lo prueba.
  final String qaNotes;

  /// El caso de soporte del que nació, si nació de uno.
  ///
  /// Muchos requerimientos empiezan como un caso: el cliente reporta algo, se
  /// revisa y resulta que no es una falla sino algo que la aplicación no
  /// hace todavía. Antes eso se volvía a escribir a mano en la hoja y se
  /// perdía el hilo — quién lo pidió, cuándo, qué se había intentado ya.
  final String? supportCaseId;
  final int? supportCaseNumber;

  final DateTime receivedAt;
  final String receivedById;
  final String receivedByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get estaAsignado => developerId != null && developerId!.isNotEmpty;

  bool get vieneDeUnCaso => supportCaseId != null && supportCaseId!.isNotEmpty;

  /// Cómo se lee el caso de origen: CS-0042.
  String get codigoCaso => supportCaseNumber == null
      ? ''
      : 'CS-${supportCaseNumber.toString().padLeft(4, '0')}';
  bool get esInterno => origin == RequirementOrigin.interno;
  bool get estaAbierto => RequirementStatus.isOpen(status);

  /// Cómo se lee el número: REQ-0007.
  String get codigo => 'REQ-${requirementNumber.toString().padLeft(4, '0')}';

  /// Para quién es, en una línea.
  String get paraQuien => clientNames.isEmpty
      ? (esInterno ? 'Interno' : 'General')
      : clientNames.join(', ');

  /// Días desde que se recibió.
  int get diasDesdeRecepcion => DateTime.now().difference(receivedAt).inDays;

  factory RequirementModel.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? {};
    return RequirementModel(
      id: doc.id,
      requirementNumber: (m['requirementNumber'] as num?)?.toInt() ?? 0,
      empresaId: m['empresaId'] as String? ?? '',
      origin: m['origin'] as String? ?? RequirementOrigin.cliente,
      clientIds: [
        for (final v in (m['clientIds'] as List<dynamic>? ?? const []))
          if (v is String) v,
      ],
      clientNames: [
        for (final v in (m['clientNames'] as List<dynamic>? ?? const []))
          if (v is String) v,
      ],
      type: m['type'] as String? ?? RequirementType.mejoras,
      module: m['module'] as String? ?? 'Otros',
      description: m['description'] as String? ?? '',
      status: m['status'] as String? ?? RequirementStatus.recibido,
      priority: m['priority'] as String? ?? RequirementPriority.sinPrioridad,
      source: m['source'] as String? ?? '',
      developerId: m['developerId'] as String?,
      developerName: m['developerName'] as String? ?? '',
      qaNotes: m['qaNotes'] as String? ?? '',
      supportCaseId: m['supportCaseId'] as String?,
      supportCaseNumber: (m['supportCaseNumber'] as num?)?.toInt(),
      receivedAt:
          (m['receivedAt'] as Timestamp?)?.toDate() ??
          (m['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      receivedById: m['receivedById'] as String? ?? '',
      receivedByName: m['receivedByName'] as String? ?? '',
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
