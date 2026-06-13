import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `groups` collection.
class GroupModel {
  final String id;
  final String name;
  final String description;
  final DateTime? createdAt;

  const GroupModel({
    required this.id,
    required this.name,
    this.description = '',
    this.createdAt,
  });

  factory GroupModel.fromMap(String id, Map<String, dynamic> map) {
    return GroupModel(
      id: id,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory GroupModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return GroupModel.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap({bool withServerTimestamp = false}) {
    return {
      'name': name,
      'description': description,
      'createdAt': withServerTimestamp
          ? FieldValue.serverTimestamp()
          : (createdAt != null ? Timestamp.fromDate(createdAt!) : null),
    };
  }
}
