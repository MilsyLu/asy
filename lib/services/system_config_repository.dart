import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../models/system_config_model.dart';

/// Reads and writes the global system configuration document
/// at `systemConfig/settings` in Firestore.
class SystemConfigRepository {
  SystemConfigRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _settingsDoc => _firestore
      .collection(FirestoreCollections.systemConfig)
      .doc(FirestoreCollections.systemConfigSettings);

  Stream<SystemConfigModel> watchConfig() {
    return _settingsDoc.snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return const SystemConfigModel();
      return SystemConfigModel.fromMap(data);
    });
  }

  Future<void> setTimeSelectionMode(String mode) {
    return _settingsDoc.set(
      {'timeSelectionMode': mode},
      SetOptions(merge: true),
    );
  }
}
