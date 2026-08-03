import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../core/constants/support_case_constants.dart';
import '../models/support_case_history_entry.dart';
import '../models/support_case_model.dart';

/// CRUD for `supportCases`, empresaId-scoped like `CatalogRepository`/
/// `PrinterConfigRepository`. Unlike those, [description] is never mutated
/// after creation — every status/priority/assignee change and every comment
/// is appended to the `history` subcollection instead (see
/// [SupportCaseHistoryEntry]), so a case's timeline is always complete.
class SupportCaseRepository {
  SupportCaseRepository({required this.empresaId, FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String empresaId;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.supportCases);

  Query<Map<String, dynamic>> get _query => _collection.where('empresaId', isEqualTo: empresaId);

  DocumentReference<Map<String, dynamic>> get _counterRef =>
      _firestore.collection(FirestoreCollections.supportCaseCounters).doc(empresaId);

  CollectionReference<Map<String, dynamic>> _historyCollection(String caseId) =>
      _collection.doc(caseId).collection(FirestoreCollections.supportCaseHistory);

  Stream<List<SupportCaseModel>> watchAll() {
    return _query.orderBy('createdAt', descending: true).snapshots().map(
        (snap) => snap.docs.map((d) => SupportCaseModel.fromDoc(d)).toList());
  }

  Stream<List<SupportCaseHistoryEntry>> watchHistory(String caseId) {
    return _historyCollection(caseId).orderBy('createdAt').snapshots().map(
        (snap) => snap.docs.map((d) => SupportCaseHistoryEntry.fromDoc(d)).toList());
  }

  Stream<SupportCaseModel?> watchCase(String caseId) {
    return _collection.doc(caseId).snapshots().map(
        (doc) => doc.exists ? SupportCaseModel.fromDoc(doc) : null);
  }

  /// Assigns the next `caseNumber` for this empresa (via a transaction on
  /// `supportCaseCounters/{empresaId}`, safe against two people creating a
  /// case at the same time) and writes the case.
  ///
  /// The first history entry is appended in a **separate** call after the
  /// transaction commits, not inside it — firestore.rules' `history`
  /// `create` rule reads the parent case doc via `get()` to check its
  /// `empresaId`, and a `get()` inside a transaction only ever sees the
  /// database's state from *before* the transaction started, never that
  /// same transaction's own not-yet-committed writes. Bundling both writes
  /// into one transaction made the parent look like it didn't exist yet to
  /// the history rule, so the whole transaction was rejected — this is what
  /// silently failed every "Nuevo caso" attempt.
  Future<String> createCase({
    required String clientName,
    String contactName = '',
    String contactPhone = '',
    required String subject,
    required String description,
    required String priority,
    List<String> tags = const [],
    String? assignedUserId,
    required DateTime reportedAt,
    required String createdBy,
    required String createdByName,
  }) async {
    final caseRef = _collection.doc();

    await _firestore.runTransaction((tx) async {
      final counterSnap = await tx.get(_counterRef);
      final nextNumber = ((counterSnap.data()?['value'] as num?)?.toInt() ?? 0) + 1;

      tx.set(_counterRef, {'value': nextNumber, 'empresaId': empresaId}, SetOptions(merge: true));

      tx.set(caseRef, {
        'caseNumber': nextNumber,
        'empresaId': empresaId,
        'clientName': clientName,
        'contactName': contactName,
        'contactPhone': contactPhone,
        'subject': subject,
        'description': description,
        'priority': priority,
        'status': SupportCaseStatus.nuevo,
        'tags': tags,
        'assignedUserId': assignedUserId,
        'attachments': <Map<String, dynamic>>[],
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': FieldValue.serverTimestamp(),
        'reportedAt': Timestamp.fromDate(reportedAt),
        'updatedAt': FieldValue.serverTimestamp(),
        'resolvedAt': null,
      });
    });

    await _appendHistory(
      caseRef.id,
      type: SupportCaseHistoryType.created,
      text: 'Caso creado.',
      authorId: createdBy,
      authorName: createdByName,
    );

    return caseRef.id;
  }

  Future<void> _appendHistory(
    String caseId, {
    required String type,
    required String text,
    required String authorId,
    required String authorName,
  }) {
    return _historyCollection(caseId).add({
      'type': type,
      'text': text,
      'authorId': authorId,
      'authorName': authorName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addComment(
    String caseId,
    String text, {
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(caseId).update({'updatedAt': FieldValue.serverTimestamp()});
    await _appendHistory(
      caseId,
      type: SupportCaseHistoryType.comment,
      text: text,
      authorId: authorId,
      authorName: authorName,
    );
  }

  Future<void> updateStatus(
    String caseId,
    String newStatus, {
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(caseId).update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
      // "Días sin resolver" freezes once the case leaves the open states,
      // and resumes counting if it's reopened.
      'resolvedAt': SupportCaseStatus.isOpen(newStatus) ? null : FieldValue.serverTimestamp(),
    });
    await _appendHistory(
      caseId,
      type: SupportCaseHistoryType.statusChanged,
      text: 'Cambió el estado a "$newStatus".',
      authorId: authorId,
      authorName: authorName,
    );
  }

  Future<void> updatePriority(
    String caseId,
    String newPriority, {
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(caseId).update({
      'priority': newPriority,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _appendHistory(
      caseId,
      type: SupportCaseHistoryType.priorityChanged,
      text: 'Cambió la prioridad a "$newPriority".',
      authorId: authorId,
      authorName: authorName,
    );
  }

  Future<void> updateAssignee(
    String caseId,
    String? newAssigneeId,
    String? newAssigneeName, {
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(caseId).update({
      'assignedUserId': newAssigneeId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _appendHistory(
      caseId,
      type: SupportCaseHistoryType.assigneeChanged,
      text: newAssigneeName != null
          ? 'Asignó el caso a $newAssigneeName.'
          : 'Quitó la asignación del caso.',
      authorId: authorId,
      authorName: authorName,
    );
  }

  Future<void> addAttachment(
    String caseId,
    SupportCaseAttachment attachment, {
    required String authorId,
    required String authorName,
  }) async {
    await _collection.doc(caseId).update({
      'attachments': FieldValue.arrayUnion([attachment.toMap()]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _appendHistory(
      caseId,
      type: SupportCaseHistoryType.attachmentAdded,
      text: 'Adjuntó "${attachment.name}".',
      authorId: authorId,
      authorName: authorName,
    );
  }

  /// Permanent delete — also clears the history subcollection first, since
  /// Firestore never cascade-deletes subcollections on its own.
  Future<void> delete(String caseId) async {
    final historySnap = await _historyCollection(caseId).get();
    final batch = _firestore.batch();
    for (final doc in historySnap.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_collection.doc(caseId));
    await batch.commit();
  }
}
