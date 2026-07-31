import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/firestore_paths.dart';

/// Wraps Firebase Auth and the side effects that must happen on
/// sign-in (last login timestamp + streak recalculation).
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = credential.user?.uid;
    if (uid != null) {
      await refreshLoginAndStreak(uid);
    }
    return credential;
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();

  /// Creates a brand-new user with Firebase Auth + a matching Firestore
  /// `users` document. Used by the admin "Gestión de usuarios" screen.
  ///
  /// Runs on a secondary [FirebaseApp] instance so the admin's own
  /// session stays active (creating a user via the primary Firebase Auth
  /// instance would otherwise sign the admin out and into the new account).
  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required String role,
    required String empresaId,
    String? groupId,
    List<String> managedGroupIds = const [],
    Map<String, bool> permissions = const {},
  }) async {
    FirebaseApp secondaryApp;
    try {
      secondaryApp = Firebase.app('adminUserCreation');
    } catch (_) {
      secondaryApp = await Firebase.initializeApp(
        name: 'adminUserCreation',
        options: Firebase.app().options,
      );
    }
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    try {
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = credential.user!.uid;
      await _firestore.collection(FirestoreCollections.users).doc(uid).set({
        'email': email.trim(),
        'name': name.trim(),
        'role': role,
        'groupId': groupId,
        'empresaId': empresaId,
        'managedGroupIds': managedGroupIds,
        'permissions': permissions,
        'fcmTokens': <String>[],
        'lastLogin': null,
        'streakDays': 0,
        'maxStreakDays': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });
    } finally {
      await secondaryAuth.signOut();
    }
  }

  /// Permanently deletes [uid]'s Firestore profile and Firebase Auth
  /// account (Sprint 7.3.1, "Eliminación permanente segura"). Runs entirely
  /// server-side via a callable Cloud Function: the client SDK can only
  /// delete the *currently signed-in* account, not an arbitrary other
  /// user's, and the function re-validates that the user has no task
  /// history before deleting anything — the client-side check in the
  /// Users admin screen is only there for instant UI feedback, never the
  /// final authority.
  Future<void> deleteUserPermanently(String uid) async {
    final callable = _functions.httpsCallable('deleteUserPermanently');
    await callable.call<void>({'uid': uid});
  }

  /// Recalculates `lastLogin` / `streakDays` / `maxStreakDays` for [uid].
  ///
  /// Streak only increases if the user logs in on a *different calendar
  /// day* than their last login (time of day is irrelevant). If a full
  /// day or more was skipped, the streak resets to 1.
  ///
  /// Called from [signIn] on every fresh login, and also by
  /// [AuthProvider]'s day-rollover check — a session left open overnight
  /// never calls [signIn] again (Firebase Auth just keeps the same token
  /// alive), so without that second call site the streak would silently
  /// stop advancing for anyone who doesn't close the tab daily.
  Future<void> refreshLoginAndStreak(String uid) async {
    final docRef = _firestore.collection(FirestoreCollections.users).doc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = snapshot.data() ?? <String, dynamic>{};

      final now = DateTime.now();
      final lastLogin = (data['lastLogin'] as Timestamp?)?.toDate();
      int streak = (data['streakDays'] as num?)?.toInt() ?? 0;
      int maxStreak = (data['maxStreakDays'] as num?)?.toInt() ?? 0;

      if (lastLogin == null) {
        streak = 1;
      } else {
        final lastDay = DateTime(lastLogin.year, lastLogin.month, lastLogin.day);
        final today = DateTime(now.year, now.month, now.day);
        final dayDiff = today.difference(lastDay).inDays;

        if (dayDiff == 1) {
          streak += 1;
        } else if (dayDiff > 1) {
          streak = 1;
        }
        // dayDiff == 0 (same day) or negative (clock skew): keep streak.
      }

      if (streak > maxStreak) maxStreak = streak;

      transaction.set(
        docRef,
        {
          'lastLogin': Timestamp.fromDate(now),
          'streakDays': streak,
          'maxStreakDays': maxStreak,
        },
        SetOptions(merge: true),
      );
    });
  }

  static String roleLabel(String role) {
    switch (role) {
      case AppRoles.superAdmin:
        return 'Super usuario';
      case AppRoles.adminEquipo:
        return 'Administrador de equipo';
      case AppRoles.trabajadorNormal:
        return 'Trabajador';
      default:
        return role;
    }
  }
}
