import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';

/// Represents a document in the `users` collection.
class AppUser {
  final String id;
  final String email;
  final String name;
  final String role;

  /// Teams this user belongs to — a `trabajador_normal` can now be a member
  /// of more than one at once (e.g. Soporte + Onboarding), so this is a
  /// list, not a single id. Empty means no team. Mirrors [managedGroupIds]'s
  /// own convention exactly.
  final List<String> groupIds;

  /// The tenant ("empresa") this user belongs to. Nullable only for legacy
  /// docs written before the multi-tenant migration backfilled every
  /// document — a null empresaId is deliberately treated as "no access" by
  /// firestore.rules (see `sameEmpresa()`), never as "every tenant's".
  final String? empresaId;

  /// Teams this user manages, only meaningful when [role] is
  /// [AppRoles.adminEquipo] — an `admin_equipo` may be assigned more than
  /// one. Empty for every other role. Defaults to `[]` so documents written
  /// before this field existed deserialize safely.
  final List<String> managedGroupIds;

  /// Granular permission flags, only meaningful when [role] is
  /// [AppRoles.adminEquipo] — see [AppPermissions] for the recognized keys.
  /// Defaults to `{}` (no permissions) so documents written before this
  /// field existed deserialize safely.
  final Map<String, bool> permissions;
  final List<String> fcmTokens;
  final DateTime? lastLogin;
  final int streakDays;
  final int maxStreakDays;
  final DateTime? createdAt;

  /// Visual preferences (FASE 3): 'system' | 'light' | 'dark'. Defaults to
  /// 'dark' for users without a stored preference, matching the app's
  /// original always-dark theme.
  final String themeMode;

  /// Visual preferences (FASE 3): 'gold' | 'blue' | 'green' | 'purple'.
  final String accentColor;

  /// URL of the user's profile photo stored in Firebase Storage. Null when
  /// no photo has been uploaded; the UI falls back to initials in that case.
  final String? photoUrl;

  /// Whether the user may sign in and receive new task assignments/
  /// notifications (Sprint 7.3.1). Documents written before this field
  /// existed have no `isActive` key at all; [fromMap] defaults those to
  /// `true` so legacy users aren't locked out without an explicit action.
  final bool isActive;

  /// Which FCM push categories this user wants to receive (Sprint 7.5.0 —
  /// replaces the boolean `pushNotificationsEnabled` from Sprint 7.4.8).
  /// One of [AppPushNotificationModes]. The in-app `notifications` record
  /// (bell badge/counter/historial) is always written server-side
  /// regardless of this preference; it only gates the FCM push itself (see
  /// `functions/src/notifications.js` `sendNotificationToUser`).
  final String pushNotificationMode;

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.groupIds = const [],
    this.empresaId,
    this.managedGroupIds = const [],
    this.permissions = const {},
    this.fcmTokens = const [],
    this.lastLogin,
    this.streakDays = 0,
    this.maxStreakDays = 0,
    this.createdAt,
    this.themeMode = 'dark',
    this.accentColor = 'gold',
    this.photoUrl,
    this.isActive = true,
    this.pushNotificationMode = AppPushNotificationModes.all,
  });

  bool get isSuperAdmin => role == AppRoles.superAdmin;

  bool get isScopedAdmin => role == AppRoles.adminEquipo;

  /// True for any kind of administrator (super_admin or admin_equipo).
  bool get isAdminOfAnyKind => isSuperAdmin || isScopedAdmin;

  /// True if this user has [key] (one of [AppPermissions]'s constants).
  /// A `super_admin` implicitly has every permission; only an `admin_equipo`
  /// reads from [permissions] at all.
  bool hasPermission(String key) =>
      isSuperAdmin || (isScopedAdmin && permissions[key] == true);

  /// True if this user may manage/see data scoped to [groupId]. A
  /// `super_admin` manages every group; an `admin_equipo` only the ones in
  /// [managedGroupIds]. `null` groupId is never "managed" by an
  /// `admin_equipo` (matches [AppRoles.trabajadorNormal] visibility, which
  /// requires an explicit group match).
  bool managesGroup(String? groupId) =>
      isSuperAdmin ||
      (isScopedAdmin && groupId != null && managedGroupIds.contains(groupId));

  /// True if this user is a member of [groupId] — one of possibly several
  /// teams. Mirrors `groupId in me().get('groupIds', [])` in firestore.rules.
  bool isInGroup(String? groupId) => groupId != null && groupIds.contains(groupId);

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? '',
      role: map['role'] as String? ?? AppRoles.trabajadorNormal,
      groupIds: (map['groupIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      empresaId: map['empresaId'] as String?,
      managedGroupIds: (map['managedGroupIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      permissions: (map['permissions'] as Map<dynamic, dynamic>?)?.map(
            (key, value) => MapEntry(key.toString(), value as bool? ?? false),
          ) ??
          const {},
      fcmTokens: (map['fcmTokens'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      lastLogin: (map['lastLogin'] as Timestamp?)?.toDate(),
      streakDays: (map['streakDays'] as num?)?.toInt() ?? 0,
      maxStreakDays: (map['maxStreakDays'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      themeMode: map['themeMode'] as String? ?? 'dark',
      accentColor: map['accentColor'] as String? ?? 'gold',
      photoUrl: map['photoUrl'] as String?,
      isActive: map['isActive'] as bool? ?? true,
      pushNotificationMode: _resolvePushNotificationMode(map),
    );
  }

  /// Sprint 7.5.0 Objetivo F: `pushNotificationMode` is the only field new
  /// writes use, but documents written under Sprint 7.4.8
  /// (`pushNotificationsEnabled`, boolean) or Sprint 7.4.7
  /// (`receiveTaskCreationPush`, boolean, admin-only) are migrated
  /// virtually on read — `false` -> [AppPushNotificationModes.none],
  /// `true` -> [AppPushNotificationModes.all] — so existing users keep
  /// their prior behavior without any write/migration script.
  static String _resolvePushNotificationMode(Map<String, dynamic> map) {
    final mode = map['pushNotificationMode'] as String?;
    if (mode != null && mode.isNotEmpty) return mode;
    final legacyEnabled = map['pushNotificationsEnabled'] as bool?;
    if (legacyEnabled != null) {
      return legacyEnabled
          ? AppPushNotificationModes.all
          : AppPushNotificationModes.none;
    }
    final legacyReceive = map['receiveTaskCreationPush'] as bool?;
    if (legacyReceive != null) {
      return legacyReceive
          ? AppPushNotificationModes.all
          : AppPushNotificationModes.none;
    }
    return AppPushNotificationModes.all;
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'groupIds': groupIds,
      'empresaId': empresaId,
      'managedGroupIds': managedGroupIds,
      'permissions': permissions,
      'fcmTokens': fcmTokens,
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'streakDays': streakDays,
      'maxStreakDays': maxStreakDays,
      'createdAt':
          createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'themeMode': themeMode,
      'accentColor': accentColor,
      'photoUrl': photoUrl,
      'isActive': isActive,
      'pushNotificationMode': pushNotificationMode,
    };
  }

  AppUser copyWith({
    String? name,
    String? role,
    List<String>? groupIds,
    List<String>? managedGroupIds,
    Map<String, bool>? permissions,
    List<String>? fcmTokens,
    DateTime? lastLogin,
    int? streakDays,
    int? maxStreakDays,
    String? themeMode,
    String? accentColor,
    String? photoUrl,
    bool? isActive,
    String? pushNotificationMode,
  }) {
    return AppUser(
      id: id,
      email: email,
      name: name ?? this.name,
      role: role ?? this.role,
      groupIds: groupIds ?? this.groupIds,
      managedGroupIds: managedGroupIds ?? this.managedGroupIds,
      permissions: permissions ?? this.permissions,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      lastLogin: lastLogin ?? this.lastLogin,
      streakDays: streakDays ?? this.streakDays,
      maxStreakDays: maxStreakDays ?? this.maxStreakDays,
      createdAt: createdAt,
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      photoUrl: photoUrl ?? this.photoUrl,
      isActive: isActive ?? this.isActive,
      pushNotificationMode: pushNotificationMode ?? this.pushNotificationMode,
    );
  }
}
