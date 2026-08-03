import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  /// Uploads [bytes] as the profile photo for [uid] and returns the
  /// public download URL. Uses [putData] (available on all platforms,
  /// including web) instead of the mobile-only [putFile].
  static Future<String> uploadProfilePhoto(String uid, Uint8List bytes) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('profile_photos/$uid/avatar.jpg');
    final snapshot = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return snapshot.ref.getDownloadURL();
  }

  static Future<void> deleteProfilePhoto(String uid) async {
    try {
      await FirebaseStorage.instance
          .ref()
          .child('profile_photos/$uid/avatar.jpg')
          .delete();
    } catch (_) {}
  }

  /// Uploads a support case attachment and returns its public download URL.
  /// Path is empresa/case-scoped to match `storage.rules`.
  static Future<String> uploadSupportCaseAttachment({
    required String empresaId,
    required String caseId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('supportCases/$empresaId/$caseId/${DateTime.now().millisecondsSinceEpoch}_$fileName');
    final snapshot = await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return snapshot.ref.getDownloadURL();
  }
}
