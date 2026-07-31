import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/constants/firestore_paths.dart';
import '../models/empresa_model.dart';

/// Reads/writes for the `empresas` (tenants) and `platformOwners`
/// collections, plus the two Cloud Functions that create/toggle a tenant —
/// used by [AuthProvider] (to watch the signed-in user's own empresa for
/// live deactivation) and by the Platform Admin Panel (Michel's own screens,
/// `lib/screens/platform/`).
class EmpresaRepository {
  EmpresaRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _empresas =>
      _firestore.collection(FirestoreCollections.empresas);

  CollectionReference<Map<String, dynamic>> get _platformOwners =>
      _firestore.collection(FirestoreCollections.platformOwners);

  /// True if [uid] is a platform owner (Michel). A one-time check, not a
  /// live watch — see `AuthProvider._onAuthChanged` for why.
  Future<bool> isPlatformOwner(String uid) async {
    final doc = await _platformOwners.doc(uid).get();
    return doc.exists;
  }

  /// Live watch of a single empresa — used by [AuthProvider] to force-sign-out
  /// every one of its users the moment it's deactivated.
  Stream<EmpresaModel?> watchEmpresa(String empresaId) {
    return _empresas.doc(empresaId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return EmpresaModel.fromDoc(doc);
    });
  }

  /// Every empresa on the platform, newest first — Platform Admin Panel only
  /// (firestore.rules restricts `list` on this collection to platform
  /// owners).
  Stream<List<EmpresaModel>> watchAllEmpresas() {
    return _empresas.orderBy('createdAt', descending: true).snapshots().map(
        (snap) => snap.docs.map((d) => EmpresaModel.fromDoc(d)).toList());
  }

  /// Creates a new empresa + its first admin account. Returns the new
  /// empresa's id. Throws [FirebaseFunctionsException] on failure (e.g. the
  /// admin email is already in use).
  Future<String> createEmpresa({
    required String empresaName,
    required String adminEmail,
    required String adminPassword,
    required String adminName,
  }) async {
    final callable = _functions.httpsCallable('createEmpresa');
    final result = await callable.call<Map<String, dynamic>>({
      'empresaName': empresaName,
      'adminEmail': adminEmail,
      'adminPassword': adminPassword,
      'adminName': adminName,
    });
    return result.data['empresaId'] as String;
  }

  /// Activates or deactivates [empresaId] — Michel's manual on/off switch
  /// (e.g. for non-payment). [reason] is only stored when deactivating.
  Future<void> toggleEmpresa({
    required String empresaId,
    required bool activo,
    String? reason,
  }) async {
    final callable = _functions.httpsCallable('toggleEmpresa');
    await callable.call<void>({
      'empresaId': empresaId,
      'activo': activo,
      'reason': reason,
    });
  }
}
