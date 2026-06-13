import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';

/// Represents a document in the `users` collection.
class AppUser {
  final String id;
  final String email;
  final String name;
  final String role;
  final String? groupId;
  final List<String> fcmTokens;
  final DateTime? lastLogin;
  final int streakDays;
  final int maxStreakDays;
  final DateTime? createdAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.groupId,
    this.fcmTokens = const [],
    this.lastLogin,
    this.streakDays = 0,
    this.maxStreakDays = 0,
    this.createdAt,
  });

  bool get isSuperAdmin => role == AppRoles.superAdmin;

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      email: map['email'] as String? ?? '',
      name: map['name'] as String? ?? '',
      role: map['role'] as String? ?? AppRoles.trabajadorNormal,
      groupId: map['groupId'] as String?,
      fcmTokens: (map['fcmTokens'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      lastLogin: (map['lastLogin'] as Timestamp?)?.toDate(),
      streakDays: (map['streakDays'] as num?)?.toInt() ?? 0,
      maxStreakDays: (map['maxStreakDays'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AppUser.fromMap(doc.id, doc.data() ?? {});
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'groupId': groupId,
      'fcmTokens': fcmTokens,
      'lastLogin': lastLogin != null ? Timestamp.fromDate(lastLogin!) : null,
      'streakDays': streakDays,
      'maxStreakDays': maxStreakDays,
      'createdAt':
          createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  AppUser copyWith({
    String? name,
    String? role,
    String? groupId,
    List<String>? fcmTokens,
    DateTime? lastLogin,
    int? streakDays,
    int? maxStreakDays,
  }) {
    return AppUser(
      id: id,
      email: email,
      name: name ?? this.name,
      role: role ?? this.role,
      groupId: groupId ?? this.groupId,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      lastLogin: lastLogin ?? this.lastLogin,
      streakDays: streakDays ?? this.streakDays,
      maxStreakDays: maxStreakDays ?? this.maxStreakDays,
      createdAt: createdAt,
    );
  }
}
