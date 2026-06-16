import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  static Future<String> uploadProfilePhoto(String uid, File file) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('profile_photos/$uid/avatar.jpg');
    final snapshot = await ref.putFile(
      file,
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
