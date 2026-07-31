import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/firestore_paths.dart';
import '../models/available_hour_model.dart';
import '../models/client_model.dart';
import '../models/group_model.dart';
import '../models/status_model.dart';
import '../models/task_type_model.dart';

/// CRUD + streams for the small "catalog" collections managed from the
/// admin panel: groups, taskTypes, statuses, availableHours and clients.
///
/// Multi-tenant: every read is pre-filtered to [empresaId] at the query
/// level (so every method built on top inherits the tenant boundary
/// automatically), and every write stamps `empresaId` into the document.
/// firestore.rules independently re-verifies this — the client-side filter
/// is not the security boundary, just what makes the app show the right
/// data (see firestore.rules' `sameEmpresa()`).
class CatalogRepository {
  CatalogRepository({required this.empresaId, FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final String empresaId;

  // ---------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _groupsCollection =>
      _firestore.collection(FirestoreCollections.groups);

  Query<Map<String, dynamic>> get _groups =>
      _groupsCollection.where('empresaId', isEqualTo: empresaId);

  Stream<List<GroupModel>> watchGroups() {
    return _groups.orderBy('name').snapshots().map(
        (snap) => snap.docs.map((d) => GroupModel.fromDoc(d)).toList());
  }

  Future<void> addGroup(String name, String description) {
    return _groupsCollection.add({
      'name': name,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
      'empresaId': empresaId,
    });
  }

  Future<void> updateGroup(String id, String name, String description,
      {String? timeSelectionMode}) {
    return _groupsCollection.doc(id).update({
      'name': name,
      'description': description,
      'timeSelectionMode': ?timeSelectionMode,
    });
  }

  Future<void> deleteGroup(String id) => _groupsCollection.doc(id).delete();

  // ---------------------------------------------------------------------
  // Task types
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _taskTypesCollection =>
      _firestore.collection(FirestoreCollections.taskTypes);

  Query<Map<String, dynamic>> get _taskTypes =>
      _taskTypesCollection.where('empresaId', isEqualTo: empresaId);

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
    return _taskTypesCollection.add({
      'name': name,
      'order': order,
      'color': ?color,
      'groupIds': groupIds,
      'empresaId': empresaId,
    });
  }

  Future<void> updateTaskType(String id, String name, int order,
      {String? color, List<String> groupIds = const []}) {
    return _taskTypesCollection.doc(id).update({
      'name': name,
      'order': order,
      'color': ?color,
      'groupIds': groupIds,
    });
  }

  Future<void> deleteTaskType(String id) =>
      _taskTypesCollection.doc(id).delete();

  // ---------------------------------------------------------------------
  // Statuses
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _statusesCollection =>
      _firestore.collection(FirestoreCollections.statuses);

  Query<Map<String, dynamic>> get _statuses =>
      _statusesCollection.where('empresaId', isEqualTo: empresaId);

  Stream<List<StatusModel>> watchStatuses() {
    return _statuses.orderBy('order').snapshots().map(
        (snap) => snap.docs.map((d) => StatusModel.fromDoc(d)).toList());
  }

  Future<List<StatusModel>> getStatuses() async {
    final snap = await _statuses.orderBy('order').get();
    return snap.docs.map((d) => StatusModel.fromDoc(d)).toList();
  }

  Future<void> addStatus(String name, int order,
      {List<String> groupIds = const []}) {
    return _statusesCollection.add({
      'name': name,
      'order': order,
      'groupIds': groupIds,
      'empresaId': empresaId,
    });
  }

  Future<void> updateStatus(String id, String name, int order,
      {List<String> groupIds = const []}) {
    return _statusesCollection
        .doc(id)
        .update({'name': name, 'order': order, 'groupIds': groupIds});
  }

  Future<void> deleteStatus(String id) => _statusesCollection.doc(id).delete();

  // ---------------------------------------------------------------------
  // Available hours
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _availableHoursCollection =>
      _firestore.collection(FirestoreCollections.availableHours);

  Query<Map<String, dynamic>> get _availableHours =>
      _availableHoursCollection.where('empresaId', isEqualTo: empresaId);

  Stream<List<AvailableHourModel>> watchAvailableHours() {
    return _availableHours.orderBy('hour').snapshots().map((snap) =>
        snap.docs.map((d) => AvailableHourModel.fromDoc(d)).toList());
  }

  Future<List<AvailableHourModel>> getAvailableHours() async {
    final snap = await _availableHours.orderBy('hour').get();
    return snap.docs.map((d) => AvailableHourModel.fromDoc(d)).toList();
  }

  Future<void> addAvailableHour(String hour,
      {List<String> groupIds = const []}) {
    return _availableHoursCollection
        .add({'hour': hour, 'groupIds': groupIds, 'empresaId': empresaId});
  }

  Future<void> updateAvailableHour(String id, String hour,
      {List<String> groupIds = const []}) {
    return _availableHoursCollection
        .doc(id)
        .update({'hour': hour, 'groupIds': groupIds});
  }

  Future<void> deleteAvailableHour(String id) =>
      _availableHoursCollection.doc(id).delete();

  // ---------------------------------------------------------------------
  // Clients — not team-scoped (no groupIds), unlike the catalogs above.
  // ---------------------------------------------------------------------
  CollectionReference<Map<String, dynamic>> get _clientsCollection =>
      _firestore.collection(FirestoreCollections.clients);

  Query<Map<String, dynamic>> get _clients =>
      _clientsCollection.where('empresaId', isEqualTo: empresaId);

  Stream<List<ClientModel>> watchClients() {
    return _clients.orderBy('name').snapshots().map(
        (snap) => snap.docs.map((d) => ClientModel.fromDoc(d)).toList());
  }

  /// Returns the new client's id — callers linking a task to it (the
  /// create-or-reuse flow in add_edit_task_page.dart/task_create_panel.dart)
  /// need it immediately, unlike the other `addX` methods above.
  Future<String> addClient(String name, String phone, {String notes = ''}) async {
    final ref = await _clientsCollection.add({
      'name': name,
      'phone': phone,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
      'empresaId': empresaId,
    });
    return ref.id;
  }

  Future<void> updateClient(String id, String name, String phone, {String notes = ''}) {
    return _clientsCollection.doc(id).update({'name': name, 'phone': phone, 'notes': notes});
  }

  Future<void> deleteClient(String id) => _clientsCollection.doc(id).delete();
}
