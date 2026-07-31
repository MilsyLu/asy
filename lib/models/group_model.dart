import 'package:cloud_firestore/cloud_firestore.dart';

import 'system_config_model.dart';

/// Represents a document in the `groups` collection.
class GroupModel {
  final String id;
  final String name;
  final String description;
  final DateTime? createdAt;

  /// The tenant ("empresa") this team belongs to. See [AppUser.empresaId].
  final String? empresaId;

  /// 'catalog' (pick from configured `availableHours`) or 'free' (any time)
  /// — replaces the old single global `systemConfig.timeSelectionMode`, now
  /// per-team. Reuses [SystemConfigModel]'s mode constants. Defaults to
  /// `catalog`, same default the global toggle used, so existing teams keep
  /// today's behavior until an admin picks 'free' for a specific team.
  final String timeSelectionMode;

  const GroupModel({
    required this.id,
    required this.name,
    this.description = '',
    this.createdAt,
    this.empresaId,
    this.timeSelectionMode = SystemConfigModel.modeCatalog,
  });

  bool get useFreePicker => timeSelectionMode == SystemConfigModel.modeFree;

  factory GroupModel.fromMap(String id, Map<String, dynamic> map) {
    return GroupModel(
      id: id,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      empresaId: map['empresaId'] as String?,
      timeSelectionMode: map['timeSelectionMode'] as String? ??
          SystemConfigModel.modeCatalog,
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
      'empresaId': empresaId,
      'timeSelectionMode': timeSelectionMode,
    };
  }
}
