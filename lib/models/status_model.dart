import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `statuses` collection.
class StatusModel {
  final String id;
  final String name;
  final int order;

  const StatusModel({
    required this.id,
    required this.name,
    this.order = 0,
  });

  factory StatusModel.fromMap(String id, Map<String, dynamic> map) {
    return StatusModel(
      id: id,
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
    );
  }

  factory StatusModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return StatusModel.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'order': order,
    };
  }
}
