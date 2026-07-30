import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `statuses` collection.
class StatusModel {
  final String id;
  final String name;
  final int order;

  /// Teams this status is offered for when creating/editing a task.
  ///
  /// Empty (the default, and what every pre-permissions-system document
  /// deserializes to since the field didn't exist) means "universal": the
  /// status is shown regardless of the selected group. Mirrors
  /// `TaskTypeModel.groupIds`.
  final List<String> groupIds;

  const StatusModel({
    required this.id,
    required this.name,
    this.order = 0,
    this.groupIds = const [],
  });

  factory StatusModel.fromMap(String id, Map<String, dynamic> map) {
    return StatusModel(
      id: id,
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      groupIds: (map['groupIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  factory StatusModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return StatusModel.fromMap(doc.id, doc.data() ?? {});
  }

  /// True if this status should be offered when [groupId] is selected.
  /// Statuses with no [groupIds] assigned are universal (see field doc).
  bool appliesToGroup(String? groupId) {
    if (groupIds.isEmpty || groupId == null) return true;
    return groupIds.contains(groupId);
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'order': order,
      'groupIds': groupIds,
    };
  }
}
