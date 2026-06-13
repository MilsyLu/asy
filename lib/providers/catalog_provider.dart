import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/app_user.dart';
import '../models/available_hour_model.dart';
import '../models/group_model.dart';
import '../models/status_model.dart';
import '../models/task_type_model.dart';
import '../services/catalog_repository.dart';
import '../services/user_repository.dart';

/// Holds the small, frequently-referenced "catalog" collections
/// (groups, taskTypes, statuses, availableHours, users) so any screen
/// can resolve IDs to human-readable names without re-subscribing.
class CatalogProvider extends ChangeNotifier {
  CatalogProvider({
    CatalogRepository? repository,
    UserRepository? userRepository,
  })  : _repository = repository ?? CatalogRepository(),
        _userRepository = userRepository ?? UserRepository() {
    _groupsSub = _repository.watchGroups().listen((v) {
      groups = v;
      notifyListeners();
    });
    _taskTypesSub = _repository.watchTaskTypes().listen((v) {
      taskTypes = v;
      notifyListeners();
    });
    _statusesSub = _repository.watchStatuses().listen((v) {
      statuses = v;
      notifyListeners();
    });
    _hoursSub = _repository.watchAvailableHours().listen((v) {
      availableHours = v;
      notifyListeners();
    });
    _usersSub = _userRepository.watchAllUsers().listen((v) {
      users = v;
      notifyListeners();
    });
  }

  final CatalogRepository _repository;
  final UserRepository _userRepository;

  late final StreamSubscription<List<GroupModel>> _groupsSub;
  late final StreamSubscription<List<TaskTypeModel>> _taskTypesSub;
  late final StreamSubscription<List<StatusModel>> _statusesSub;
  late final StreamSubscription<List<AvailableHourModel>> _hoursSub;
  late final StreamSubscription<List<AppUser>> _usersSub;

  List<GroupModel> groups = [];
  List<TaskTypeModel> taskTypes = [];
  List<StatusModel> statuses = [];
  List<AvailableHourModel> availableHours = [];
  List<AppUser> users = [];

  bool get isReady =>
      groups.isNotEmpty ||
      taskTypes.isNotEmpty ||
      statuses.isNotEmpty ||
      availableHours.isNotEmpty ||
      users.isNotEmpty;

  GroupModel? groupById(String? id) {
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  String groupName(String? id) => groupById(id)?.name ?? 'Sin grupo';

  TaskTypeModel? taskTypeById(String? id) {
    if (id == null) return null;
    for (final t in taskTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  String taskTypeName(String? id) => taskTypeById(id)?.name ?? '-';

  StatusModel? statusById(String? id) {
    if (id == null) return null;
    for (final s in statuses) {
      if (s.id == id) return s;
    }
    return null;
  }

  String statusName(String? id) => statusById(id)?.name ?? '-';

  /// Finds the status document whose name matches one of the well-known
  /// names in [AppStatusNames] (case-insensitive).
  StatusModel? statusByName(String name) {
    for (final s in statuses) {
      if (s.name.toLowerCase() == name.toLowerCase()) return s;
    }
    return null;
  }

  TaskTypeModel? taskTypeByName(String name) {
    for (final t in taskTypes) {
      if (t.name.toLowerCase() == name.toLowerCase()) return t;
    }
    return null;
  }

  AppUser? userById(String? id) {
    if (id == null) return null;
    for (final u in users) {
      if (u.id == id) return u;
    }
    return null;
  }

  String userName(String? id) => userById(id)?.name ?? 'Sin asignar';

  List<AppUser> usersInGroup(String? groupId) {
    if (groupId == null) return const [];
    return users.where((u) => u.groupId == groupId).toList();
  }

  /// Returns the id of the "Pendiente" status, falling back to the
  /// first status by `order` if no match is found.
  String? get pendingStatusId =>
      statusByName(AppStatusNames.pendiente)?.id ??
      (statuses.isNotEmpty ? statuses.first.id : null);

  String? get completedStatusId => statusByName(AppStatusNames.completada)?.id;

  String? get rescheduledStatusId =>
      statusByName(AppStatusNames.reprogramada)?.id;

  @override
  void dispose() {
    _groupsSub.cancel();
    _taskTypesSub.cancel();
    _statusesSub.cancel();
    _hoursSub.cancel();
    _usersSub.cancel();
    super.dispose();
  }
}
