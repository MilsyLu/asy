import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `printerConfigs` collection — one record per
/// VinApp Print installer client. Only [clientName] is required; every
/// VinApp Print setting lives in the flat [fields] map, keyed by
/// `PrinterConfigSchema`'s field keys (see
/// `core/constants/printer_config_schema.dart`) — not modeled as individual
/// typed fields here, since the ~88-field schema can grow/change without a
/// data migration this way.
class PrinterConfigModel {
  final String id;
  final String clientName;
  final Map<String, dynamic> fields;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? empresaId;

  const PrinterConfigModel({
    required this.id,
    required this.clientName,
    this.fields = const {},
    this.createdAt,
    this.updatedAt,
    this.empresaId,
  });

  factory PrinterConfigModel.fromMap(String id, Map<String, dynamic> map) {
    return PrinterConfigModel(
      id: id,
      clientName: map['clientName'] as String? ?? '',
      fields: Map<String, dynamic>.from(map['fields'] as Map? ?? {}),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      empresaId: map['empresaId'] as String?,
    );
  }

  factory PrinterConfigModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return PrinterConfigModel.fromMap(doc.id, doc.data() ?? {});
  }
}
