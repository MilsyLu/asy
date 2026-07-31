import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/constants/firestore_paths.dart';
import '../models/printer_config_model.dart';

/// One image to send to the AI extraction Cloud Function. Never persisted —
/// the bytes live only for the duration of the request.
class PrinterConfigImageInput {
  const PrinterConfigImageInput({required this.base64Data, required this.mediaType});

  /// Raw base64 image data, no `data:image/...;base64,` prefix.
  final String base64Data;

  /// e.g. "image/jpeg", "image/png".
  final String mediaType;
}

/// CRUD for `printerConfigs`, plus the one Cloud Function call that sends
/// VinApp Print screenshots to Claude for extraction. Multi-tenant like
/// `CatalogRepository` (empresaId-filtered reads, empresaId-stamped writes)
/// — the actual security boundary is firestore.rules' `printerConfigs`
/// block, not this class. Kept separate from `CatalogRepository` since this
/// is a different bounded context (a VinApp Print-specific tool with an AI
/// side-effect) rather than another simple catalog collection.
class PrinterConfigRepository {
  PrinterConfigRepository({
    required this.empresaId,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String empresaId;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(FirestoreCollections.printerConfigs);

  Query<Map<String, dynamic>> get _query =>
      _collection.where('empresaId', isEqualTo: empresaId);

  Stream<List<PrinterConfigModel>> watchAll() {
    return _query.orderBy('clientName').snapshots().map(
        (snap) => snap.docs.map((d) => PrinterConfigModel.fromDoc(d)).toList());
  }

  Future<String> add(String clientName, Map<String, dynamic> fields) async {
    final ref = await _collection.add({
      'clientName': clientName,
      'fields': fields,
      'empresaId': empresaId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(String id, String clientName, Map<String, dynamic> fields) {
    return _collection.doc(id).update({
      'clientName': clientName,
      'fields': fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _collection.doc(id).delete();

  /// Sends [images] to the `extractPrinterConfigFromImages` Cloud Function
  /// and returns only the partial field map Claude could read with
  /// confidence — the caller merges this into the form's in-memory state
  /// for the admin to review before saving. Nothing here (or server-side)
  /// persists the images.
  Future<Map<String, dynamic>> extractFromImages(
    List<PrinterConfigImageInput> images,
  ) async {
    final callable = _functions.httpsCallable('extractPrinterConfigFromImages');
    final result = await callable.call<Map<String, dynamic>>({
      'images': images
          .map((i) => {'data': i.base64Data, 'mediaType': i.mediaType})
          .toList(),
    });
    return Map<String, dynamic>.from(result.data['fields'] as Map? ?? {});
  }
}
