import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a document in the `availableHours` collection.
class AvailableHourModel {
  final String id;
  final String hour; // "HH:MM"

  const AvailableHourModel({
    required this.id,
    required this.hour,
  });

  factory AvailableHourModel.fromMap(String id, Map<String, dynamic> map) {
    return AvailableHourModel(
      id: id,
      hour: map['hour'] as String? ?? '00:00',
    );
  }

  factory AvailableHourModel.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return AvailableHourModel.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap() {
    return {'hour': hour};
  }
}
