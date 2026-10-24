import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../core/constants/requirement_constants.dart';
import '../models/requirement_model.dart';

/// CRUD de `requirements`, acotado por empresa igual que el resto.
///
/// Sigue la forma de `SupportCaseRepository`, que ya está probada: la
/// descripción no se reescribe nunca después de crear el requerimiento, y
/// cada cambio de estado, de responsable o cada nota queda como un evento en
/// la subcolección `events`. Así el recorrido completo está siempre ahí, que
/// es justo lo que la hoja de cálculo no podía dar: allí un cambio de estado
/// pisaba el anterior y no quedaba ni quién ni cuándo.
class RequirementRepository {
  RequirementRepository({required this.empresaId, FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String empresaId;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.requirements);

  Query<Map<String, dynamic>> get _query =>
      _collection.where('empresaId', isEqualTo: empresaId);

  DocumentReference<Map<String, dynamic>> get _counterRef => _firestore
      .collection(FirestoreCollections.requirementCounters)
      .doc(empresaId);

  CollectionReference<Map<String, dynamic>> _eventsCollection(String id) =>
      _collection.doc(id).collection(FirestoreCollections.requirementEvents);

  CollectionReference<Map<String, dynamic>> get _developersCollection =>
      _firestore.collection(FirestoreCollections.developers);

  // ── desarrolladores ────────────────────────────────────────────────────

  /// El equipo técnico al que se le asignan los requerimientos.
  ///
  /// Entran y salen, por eso se administra desde la app y no es una lista
  /// escrita en el código.
  Stream<List<DeveloperModel>> watchDevelopers() {
    return _developersCollection
        .where('empresaId', isEqualTo: empresaId)
        .orderBy('name')
        .snapshots()
        .map((s) => s.docs.map(DeveloperModel.fromDoc).toList());
  }

  Future<void> addDeveloper(String name) {
    return _developersCollection.add({
      'name': name.trim(),
      'isActive': true,
      'empresaId': empresaId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setDeveloperActive(String id, bool active) =>
      _developersCollection.doc(id).update({'isActive': active});

  Future<void> renameDeveloper(String id, String name) =>
      _developersCollection.doc(id).update({'name': name.trim()});

  /// Sólo se puede borrar del todo a alguien que no tenga requerimientos; si
  /// los tiene, se desactiva. Borrarlo dejaría esos requerimientos con un
  /// responsable que no existe.
  Future<bool> deleteDeveloperIfUnused(String id) async {
    final usados = await _query.where('developerId', isEqualTo: id).limit(1).get();
    if (usados.docs.isNotEmpty) return false;
    await _developersCollection.doc(id).delete();
    return true;
  }

  // ── requerimientos ─────────────────────────────────────────────────────

  Stream<List<RequirementModel>> watchAll() {
    return _query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(RequirementModel.fromDoc).toList());
  }

  Stream<RequirementModel?> watchOne(String id) {
    return _collection
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? RequirementModel.fromDoc(d) : null);
  }

  Stream<List<RequirementEvent>> watchEvents(String id) {
    return _eventsCollection(id)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(RequirementEvent.fromDoc).toList());
  }

  /// Asigna el siguiente número y escribe el requerimiento.
  ///
  /// El primer evento se agrega **después** de que la transacción confirma,
  /// no dentro: la regla de `events` lee el documento padre con `get()` para
  /// comprobar su empresa, y un `get()` dentro de una transacción sólo ve el
  /// estado anterior de la base, nunca las escrituras de esa misma
  /// transacción. Es exactamente el error que hacía fallar en silencio cada
  /// "Nuevo caso" cuando se construyó Casos de Soporte.
  Future<String> create({
    required String origin,
    required List<String> clientIds,
    required List<String> clientNames,
    required String type,
    required String module,
    required String description,
    required String priority,
    required String source,
    String? developerId,
    String developerName = '',
    required String createdById,
    required String createdByName,
    DateTime? receivedAt,
  }) async {
    final ref = _collection.doc();
    final cuando = receivedAt ?? DateTime.now();

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(_counterRef);
      final siguiente = ((snap.data()?['value'] as num?)?.toInt() ?? 0) + 1;
      tx.set(_counterRef, {
        'value': siguiente,
        'empresaId': empresaId,
      }, SetOptions(merge: true));

      tx.set(ref, {
        'requirementNumber': siguiente,
        'empresaId': empresaId,
        'origin': origin,
        'clientIds': clientIds,
        'clientNames': clientNames,
        'type': type,
        'module': module,
        'description': description,
        'status': RequirementStatus.recibido,
        'priority': priority,
        'source': source,
        'developerId': developerId,
        'developerName': developerName,
        'qaNotes': '',
        // Los tres que más se olvidaban en la hoja. Aquí no se preguntan:
        // los pone la app, así que no pueden faltar.
        'receivedAt': Timestamp.fromDate(cuando),
        'receivedById': createdById,
        'receivedByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await addEvent(
      ref.id,
      type: RequirementEvent.creado,
      text: 'Requerimiento creado.',
      authorId: createdById,
      authorName: createdByName,
    );
    return ref.id;
  }

  Future<void> addEvent(
    String id, {
    required String type,
    required String text,
    required String authorId,
    required String authorName,
  }) {
    return _eventsCollection(id).add({
      'type': type,
      'text': text,
      'authorId': authorId,
      'authorName': authorName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> changeStatus(
    String id, {
    required String from,
    required String to,
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(id).update({
      'status': to,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addEvent(
      id,
      type: RequirementEvent.estado,
      text: 'Cambió el estado de "$from" a "$to".',
      authorId: authorId,
      authorName: authorName,
    );
  }

  Future<void> assignDeveloper(
    String id, {
    required String? developerId,
    required String developerName,
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(id).update({
      'developerId': developerId,
      'developerName': developerName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addEvent(
      id,
      type: RequirementEvent.asignado,
      text: developerId == null
          ? 'Quedó sin responsable asignado.'
          : 'Asignado a $developerName.',
      authorId: authorId,
      authorName: authorName,
    );
  }

  /// Corrige los datos del requerimiento.
  ///
  /// La descripción sí se puede cambiar, a diferencia de un caso de soporte.
  /// Allí la descripción es lo que dijo el cliente y no se toca; aquí es la
  /// especificación de lo que hay que construir, y se afina a medida que se
  /// entiende mejor. Los 48 que llegaron de la hoja traen además erratas y
  /// textos a medio escribir que hay que poder arreglar.
  ///
  /// Queda registrado en la línea de tiempo: se ve que cambió y quién, aunque
  /// no el texto anterior — guardar cada versión de una especificación de
  /// 1.500 caracteres es más de lo que este módulo necesita hoy.
  Future<void> updateDetails(
    String id, {
    required String origin,
    required List<String> clientIds,
    required List<String> clientNames,
    required String type,
    required String module,
    required String description,
    required String priority,
    required String source,
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(id).update({
      'origin': origin,
      'clientIds': clientIds,
      'clientNames': clientNames,
      'type': type,
      'module': module,
      'description': description,
      'priority': priority,
      'source': source,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addEvent(
      id,
      type: RequirementEvent.editado,
      text: 'Editó los datos del requerimiento.',
      authorId: authorId,
      authorName: authorName,
    );
  }

  Future<void> updatePriority(String id, String priority) =>
      _collection.doc(id).update({
        'priority': priority,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> updateQaNotes(
    String id, {
    required String notes,
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(id).update({
      'qaNotes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await addEvent(
      id,
      type: RequirementEvent.notaQa,
      text: 'Actualizó las notas de QA.',
      authorId: authorId,
      authorName: authorName,
    );
  }

  Future<void> delete(String id) => _collection.doc(id).delete();
}
