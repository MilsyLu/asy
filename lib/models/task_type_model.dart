import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `taskTypes` collection.
class TaskTypeModel {
  final String id;
  final String name;
  final int order;
  final String? color; // optional hex color string, e.g. "#D4AF37"

  /// Groups this task type is offered for when creating/editing a task.
  ///
  /// Empty (the default, and what every pre-Sprint-5.4 document deserializes
  /// to since the field didn't exist) means "universal": the type is shown
  /// regardless of the selected group. This keeps existing task types
  /// visible everywhere until an admin explicitly restricts them — see
  /// [appliesToGroup].
  final List<String> groupIds;

  const TaskTypeModel({
    required this.id,
    required this.name,
    this.order = 0,
    this.color,
    this.groupIds = const [],
  });

  factory TaskTypeModel.fromMap(String id, Map<String, dynamic> map) {
    return TaskTypeModel(
      id: id,
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      color: map['color'] as String?,
      groupIds: (map['groupIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  factory TaskTypeModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return TaskTypeModel.fromMap(doc.id, doc.data() ?? {});
  }

  /// True if this type should be offered when [groupId] is selected.
  /// Types with no [groupIds] assigned are universal (see field doc).
  bool appliesToGroup(String? groupId) {
    if (groupIds.isEmpty || groupId == null) return true;
    return groupIds.contains(groupId);
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'order': order,
      'color': ?color,
      'groupIds': groupIds,
    };
  }
}
