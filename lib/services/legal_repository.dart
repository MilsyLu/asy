import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/legal/legal_documents.dart';

/// Una aceptación: quién aceptó qué documento, en qué versión y cuándo.
///
/// Guarda el nombre y el correo copiados, no sólo el id del usuario. Si la
/// cuenta se borra —que es un derecho del titular— el registro tiene que
/// seguir diciendo por sí solo quién aceptó: un id huérfano no prueba nada.
class LegalAcceptance {
  const LegalAcceptance({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.documentoId,
    required this.documentoTitulo,
    required this.version,
    required this.aceptadoEn,
    this.empresaId,
  });

  final String userId;
  final String userName;
  final String userEmail;
  final String documentoId;
  final String documentoTitulo;
  final String version;
  final DateTime? aceptadoEn;
  final String? empresaId;

  factory LegalAcceptance.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? {};
    return LegalAcceptance(
      userId: m['userId'] as String? ?? '',
      userName: m['userName'] as String? ?? '',
      userEmail: m['userEmail'] as String? ?? '',
      documentoId: m['documentoId'] as String? ?? '',
      documentoTitulo: m['documentoTitulo'] as String? ?? '',
      version: m['version'] as String? ?? '',
      aceptadoEn: (m['aceptadoEn'] as Timestamp?)?.toDate(),
      empresaId: m['empresaId'] as String?,
    );
  }
}

/// Guarda y consulta las aceptaciones de los documentos legales.
///
/// La colección `legalAcceptances` sólo admite crear: nadie, ni un
/// superadministrador, puede modificar ni borrar un registro (ver
/// firestore.rules). Un registro que se puede editar después no sirve como
/// prueba, y probar la autorización es exactamente lo que la Ley 1581 de
/// 2012 exige poder hacer.
class LegalRepository {
  LegalRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('legalAcceptances');

  /// El identificador del registro.
  ///
  /// Empieza por el uid de quien acepta, y la regla de seguridad lo exige
  /// así: nadie puede sembrar una aceptación en el espacio de otro.
  ///
  /// Termina en el instante, de modo que **cada aceptación es un registro
  /// nuevo** y ninguna pisa a la anterior. Con un identificador fijo,
  /// aceptar dos veces el mismo documento era una escritura sobre algo que
  /// ya existía, y la regla —que prohíbe modificar— la rechazaba: a quien
  /// le reapareciera la pantalla por un corte de red le salía un error de
  /// permisos y se quedaba sin poder entrar. Dos registros de lo mismo no
  /// estorban; perder el acceso sí.
  static String idDe(String uid, LegalDoc doc, DateTime cuando) =>
      '${uid}__${doc.clave}__${cuando.millisecondsSinceEpoch}';

  /// Qué documentos vigentes le faltan por aceptar a [uid].
  ///
  /// Una sola consulta por sesión: trae lo que esa persona ha aceptado y el
  /// cruce se hace aquí. Preguntar documento por documento costaría una
  /// lectura por cada uno cada vez que alguien abre la aplicación.
  Future<List<LegalDoc>> pendientesDe(String uid) async {
    final snap = await _collection.where('userId', isEqualTo: uid).get();
    final aceptados = {
      for (final d in snap.docs)
        '${d.data()['documentoId']}_v${d.data()['version']}',
    };
    return [
      for (final doc in LegalDocs.todos)
        if (!aceptados.contains(doc.clave)) doc,
    ];
  }

  /// Registra la aceptación de [docs] por parte de esa persona.
  ///
  /// En un solo lote: o quedan todos o no queda ninguno. Aceptar "la mitad
  /// de los documentos" no es un estado que deba existir — la pantalla pide
  /// los dos juntos.
  Future<void> aceptar({
    required String uid,
    required String nombre,
    required String correo,
    required String? empresaId,
    required List<LegalDoc> docs,
    required String origen,
  }) async {
    final lote = _firestore.batch();
    // La hora del equipo sólo decide el nombre del registro. La fecha que
    // vale es `aceptadoEn`, que la pone el servidor: un reloj mal puesto no
    // puede fechar una autorización.
    final ahora = DateTime.now();
    for (final doc in docs) {
      lote.set(_collection.doc(idDe(uid, doc, ahora)), {
        'userId': uid,
        'userName': nombre,
        'userEmail': correo,
        'documentoId': doc.id,
        'documentoTitulo': doc.titulo,
        'version': doc.version,
        'empresaId': empresaId,
        'origen': origen,
        'aceptadoEn': FieldValue.serverTimestamp(),
      });
    }
    await lote.commit();
  }

  /// Lo que [uid] ha aceptado, de lo más reciente a lo más viejo. Es lo que
  /// se le muestra en Configuración, y lo que se entrega si alguien pide
  /// prueba de su autorización.
  Stream<List<LegalAcceptance>> watchDe(String uid) {
    return _collection.where('userId', isEqualTo: uid).snapshots().map((s) {
      final lista = s.docs.map(LegalAcceptance.fromDoc).toList();
      lista.sort((a, b) {
        final fa = a.aceptadoEn;
        final fb = b.aceptadoEn;
        if (fa == null || fb == null) return 0;
        return fb.compareTo(fa);
      });
      return lista;
    });
  }
}
