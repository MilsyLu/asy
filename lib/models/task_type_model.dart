import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `taskTypes` collection.
class TaskTypeModel {
  final String id;
  final String name;
  final int order;
  final String? color; // optional hex color string, e.g. "#D4AF37"

  const TaskTypeModel({
    required this.id,
    required this.name,
    this.order = 0,
    this.color,
  });

  factory TaskTypeModel.fromMap(String id, Map<String, dynamic> map) {
    return TaskTypeModel(
      id: id,
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      color: map['color'] as String?,
    );
  }

  factory TaskTypeModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return TaskTypeModel.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'order': order,
      'color': ?color,
    };
  }
}
