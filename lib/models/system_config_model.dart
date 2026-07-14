/// Global system configuration stored in `systemConfig/settings`.
class SystemConfigModel {
  static const String modeCatalog = 'catalog';
  static const String modeFree = 'free';

  final String timeSelectionMode;

  const SystemConfigModel({this.timeSelectionMode = modeCatalog});

  factory SystemConfigModel.fromMap(Map<String, dynamic> data) {
    return SystemConfigModel(
      timeSelectionMode: (data['timeSelectionMode'] as String?) ?? modeCatalog,
    );
  }

  Map<String, dynamic> toMap() => {'timeSelectionMode': timeSelectionMode};

  bool get useFreePicker => timeSelectionMode == modeFree;
}
