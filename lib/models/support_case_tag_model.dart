import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `supportCaseTags` collection — the
/// admin-curated tag catalog. Any signed-in user can read this list to
/// apply tags to a case; only `manageSupportCases` can add/rename/remove
/// entries here (see firestore.rules).
class SupportCaseTagModel {
  const SupportCaseTagModel({
    required this.id,
    required this.name,
    required this.empresaId,
    this.createdAt,
  });

  final String id;
  final String name;
  final String empresaId;
  final DateTime? createdAt;

  factory SupportCaseTagModel.fromMap(String id, Map<String, dynamic> map) {
    return SupportCaseTagModel(
      id: id,
      name: map['name'] as String? ?? '',
      empresaId: map['empresaId'] as String? ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory SupportCaseTagModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return SupportCaseTagModel.fromMap(doc.id, doc.data() ?? {});
  }
}
