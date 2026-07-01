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
}
