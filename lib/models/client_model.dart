import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `clients` collection.
///
/// Not team-scoped (unlike GroupModel/StatusModel/TaskTypeModel) — a client
/// isn't owned by one equipo, so there's no `groupIds` field here.
class ClientModel {
  final String id;
  final String name;
  final String phone;
  final String notes;
  final DateTime? createdAt;

  /// The tenant ("empresa") this client belongs to. See `AppUser.empresaId`.
  final String? empresaId;

  const ClientModel({
    required this.id,
    required this.name,
    this.phone = '',
    this.notes = '',
    this.createdAt,
    this.empresaId,
  });

  factory ClientModel.fromMap(String id, Map<String, dynamic> map) {
    return ClientModel(
      id: id,
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      empresaId: map['empresaId'] as String?,
    );
  }

  factory ClientModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ClientModel.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap({bool withServerTimestamp = false}) {
    return {
      'name': name,
      'phone': phone,
      'notes': notes,
      'createdAt': withServerTimestamp
          ? FieldValue.serverTimestamp()
          : (createdAt != null ? Timestamp.fromDate(createdAt!) : null),
      'empresaId': empresaId,
    };
  }
}
