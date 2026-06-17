import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../models/available_hour_model.dart';
import '../models/group_model.dart';
import '../models/status_model.dart';
import '../models/task_type_model.dart';

/// CRUD + streams for the small "catalog" collections managed from the
/// admin panel: groups, taskTypes, statuses and availableHours.
class CatalogRepository {
  CatalogRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  // ---------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _groups =>
      _firestore.collection(FirestoreCollections.groups);

  Stream<List<GroupModel>> watchGroups() {
    return _groups.orderBy('name').snapshots().map(
        (snap) => snap.docs.map((d) => GroupModel.fromDoc(d)).toList());
  }

  Future<void> addGroup(String name, String description) {
    return _groups.add({
      'name': name,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGroup(String id, String name, String description) {
    return _groups.doc(id).update({'name': name, 'description': description});
  }

  Future<void> deleteGroup(String id) => _groups.doc(id).delete();

  // ---------------------------------------------------------------------
  // Task types
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _taskTypes =>
      _firestore.collection(FirestoreCollections.taskTypes);

  Stream<List<TaskTypeModel>> watchTaskTypes() {
    return _taskTypes.orderBy('order').snapshots().map(
        (snap) => snap.docs.map((d) => TaskTypeModel.fromDoc(d)).toList());
  }

  Future<List<TaskTypeModel>> getTaskTypes() async {
    final snap = await _taskTypes.orderBy('order').get();
    return snap.docs.map((d) => TaskTypeModel.fromDoc(d)).toList();
  }

  Future<void> addTaskType(String name, int order,
      {String? color, List<String> groupIds = const []}) {
    return _taskTypes.add({
      'name': name,
      'order': order,
      'color': ?color,
      'groupIds': groupIds,
    });
  }

  Future<void> updateTaskType(String id, String name, int order,
      {String? color, List<String> groupIds = const []}) {
    return _taskTypes.doc(id).update({
      'name': name,
      'order': order,
      'color': ?color,
      'groupIds': groupIds,
    });
  }

  Future<void> deleteTaskType(String id) => _taskTypes.doc(id).delete();

  // ---------------------------------------------------------------------
  // Statuses
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _statuses =>
      _firestore.collection(FirestoreCollections.statuses);

  Stream<List<StatusModel>> watchStatuses() {
    return _statuses.orderBy('order').snapshots().map(
        (snap) => snap.docs.map((d) => StatusModel.fromDoc(d)).toList());
  }

  Future<List<StatusModel>> getStatuses() async {
    final snap = await _statuses.orderBy('order').get();
    return snap.docs.map((d) => StatusModel.fromDoc(d)).toList();
  }

  Future<void> addStatus(String name, int order) {
    return _statuses.add({'name': name, 'order': order});
  }

  Future<void> updateStatus(String id, String name, int order) {
    return _statuses.doc(id).update({'name': name, 'order': order});
  }

  Future<void> deleteStatus(String id) => _statuses.doc(id).delete();

  // ---------------------------------------------------------------------
  // Available hours
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _availableHours =>
      _firestore.collection(FirestoreCollections.availableHours);

  Stream<List<AvailableHourModel>> watchAvailableHours() {
    return _availableHours.orderBy('hour').snapshots().map((snap) =>
        snap.docs.map((d) => AvailableHourModel.fromDoc(d)).toList());
  }

  Future<List<AvailableHourModel>> getAvailableHours() async {
    final snap = await _availableHours.orderBy('hour').get();
    return snap.docs.map((d) => AvailableHourModel.fromDoc(d)).toList();
  }

  Future<void> addAvailableHour(String hour) {
    return _availableHours.add({'hour': hour});
  }

  Future<void> updateAvailableHour(String id, String hour) {
    return _availableHours.doc(id).update({'hour': hour});
  }

  Future<void> deleteAvailableHour(String id) =>
      _availableHours.doc(id).delete();
}
