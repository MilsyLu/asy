/// Firestore collection name constants.
class FirestoreCollections {
  FirestoreCollections._();

  static const String users = 'users';
  static const String tasks = 'tasks';
  static const String groups = 'groups';
  static const String taskTypes = 'taskTypes';
  static const String statuses = 'statuses';
  static const String availableHours = 'availableHours';
  static const String clients = 'clients';
  static const String notifications = 'notifications';
  static const String empresas = 'empresas';
  static const String platformOwners = 'platformOwners';
  static const String printerConfigs = 'printerConfigs';
  static const String supportCases = 'supportCases';
  static const String supportCaseCounters = 'supportCaseCounters';
  static const String supportCaseHistory = 'history';
  static const String supportCaseTags = 'supportCaseTags';

  /// Requerimientos: lo que los clientes piden que VinApp haga. Reemplaza la
  /// hoja de cálculo que se compartía con el área de soporte.
  static const String requirements = 'requirements';
  static const String requirementCounters = 'requirementCounters';
  static const String requirementEvents = 'events';

  /// Módulos que el equipo agregó desde el formulario, además de los
  /// que trae [RequirementModule.all].
  static const String requirementModules = 'requirementModules';

  /// El equipo técnico al que se asignan los requerimientos. No son usuarios
  /// de CheCu: están del otro lado, construyendo VinApp.
  static const String developers = 'developers';

  // Global system configuration
  static const String systemConfig = 'systemConfig';
  static const String systemConfigSettings = 'settings';
}
