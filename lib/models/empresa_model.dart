import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `empresas` collection — a tenant of the
/// platform. Provisioned only by the platform owner (Michel) via the
/// `createEmpresa` Cloud Function; toggled via `toggleEmpresa`.
class EmpresaModel {
  final String id;
  final String name;
  final bool activo;
  final DateTime? createdAt;
  final String? createdBy;
  final DateTime? suspendedAt;
  final String? suspendedReason;

  const EmpresaModel({
    required this.id,
    required this.name,
    this.activo = true,
    this.createdAt,
    this.createdBy,
    this.suspendedAt,
    this.suspendedReason,
  });

  factory EmpresaModel.fromMap(String id, Map<String, dynamic> map) {
    return EmpresaModel(
      id: id,
      name: map['name'] as String? ?? '',
      activo: map['activo'] as bool? ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      createdBy: map['createdBy'] as String?,
      suspendedAt: (map['suspendedAt'] as Timestamp?)?.toDate(),
      suspendedReason: map['suspendedReason'] as String?,
    );
  }

  factory EmpresaModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return EmpresaModel.fromMap(doc.id, doc.data() ?? {});
  }
}
