import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `availableHours` collection.
class AvailableHourModel {
  final String id;
  final String hour; // "HH:MM"

  /// Teams this hour slot is offered for when creating/editing a task.
  ///
  /// Empty (the default, and what every pre-permissions-system document
  /// deserializes to since the field didn't exist) means "universal": the
  /// slot is shown regardless of the selected group. Mirrors
  /// `TaskTypeModel.groupIds`.
  final List<String> groupIds;

  const AvailableHourModel({
    required this.id,
    required this.hour,
    this.groupIds = const [],
  });

  factory AvailableHourModel.fromMap(String id, Map<String, dynamic> map) {
    return AvailableHourModel(
      id: id,
      hour: map['hour'] as String? ?? '00:00',
      groupIds: (map['groupIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  factory AvailableHourModel.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return AvailableHourModel.fromMap(doc.id, doc.data() ?? {});
  }

  /// True if this hour slot should be offered when [groupId] is selected.
  /// Slots with no [groupIds] assigned are universal (see field doc).
  bool appliesToGroup(String? groupId) {
    if (groupIds.isEmpty || groupId == null) return true;
    return groupIds.contains(groupId);
  }

  Map<String, dynamic> toMap() {
    return {'hour': hour, 'groupIds': groupIds};
  }
}
