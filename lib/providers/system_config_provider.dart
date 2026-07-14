import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/system_config_model.dart';
import '../services/system_config_repository.dart';

/// Streams the global system configuration from Firestore and exposes it
/// reactively. Placed in the Navigator builder so all routes can read it.
class SystemConfigProvider extends ChangeNotifier {
  SystemConfigProvider({SystemConfigRepository? repository})
      : _repository = repository ?? SystemConfigRepository() {
    _sub = _repository.watchConfig().listen((cfg) {
      _config = cfg;
      notifyListeners();
    });
  }

  final SystemConfigRepository _repository;
  late final StreamSubscription<SystemConfigModel> _sub;

  SystemConfigModel _config = const SystemConfigModel();

  SystemConfigModel get config => _config;

  Future<void> setTimeSelectionMode(String mode) =>
      _repository.setTimeSelectionMode(mode);

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
