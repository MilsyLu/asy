import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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

  /// Signs in with Google, but only for people an administrator already
  /// provisioned — the button on the login screen is a faster way *in*, never
  /// a way to sign *up*.
  ///
  /// Google itself will happily authenticate any Google account on earth, and
  /// Firebase will happily mint an Auth user for it. Neither of them knows
  /// anything about CheCu's tenants. Without the check below, a stranger who
  /// found the login URL would end up with a real Auth account, no
  /// `users/{uid}` profile, no empresa and no claim — locked out of every
  /// document by the security rules (that part holds), but stranded on a login
  /// screen that just bounces them back with no explanation, and leaving an
  /// orphan account behind in the project every time.
  ///
  /// So the credential is treated as a *claim of identity*, and CheCu's own
  /// records decide whether it grants entry: either a `users/{uid}` profile
  /// (an ordinary member of an empresa) or `platformOwners/{uid}` (Michel, who
  /// by design has no user profile at all — checking only `users` would lock
  /// him out of his own platform console). Anything else is rejected, and an
  /// account this popup just created is deleted again on the way out so the
  /// attempt leaves nothing behind.
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      // Without this, Google silently reuses whatever session the browser
      // already has, so somebody on a shared computer can never reach the
      // account chooser to pick a different one.
      ..setCustomParameters({'prompt': 'select_account'});

    final credential = kIsWeb
        ? await _auth.signInWithPopup(provider)
        : await _auth.signInWithProvider(provider);

    final user = credential.user;
    if (user == null) {
      await _auth.signOut();
      throw const AccountNotProvisionedException(null);
    }

    final provisioned = await _isProvisioned(user.uid);
    if (!provisioned) {
      // Only delete what this very popup brought into existence. An existing
      // account that momentarily fails the check (a profile mid-deletion, say)
      // must survive — signing out is enough to keep it out.
      if (credential.additionalUserInfo?.isNewUser ?? false) {
        try {
          await user.delete();
        } catch (_) {
          // Best effort. The account is harmless either way: it owns no
          // profile, so every rule in firestore.rules denies it.
        }
      }
      await _auth.signOut();
      throw AccountNotProvisionedException(user.email);
    }

    // Deliberately not called for platform owners: `refreshLoginAndStreak`
    // writes with `SetOptions(merge: true)`, which on an account that has no
    // `users/{uid}` document would *create* one — inventing a half-formed
    // tenant profile for somebody who is not a tenant user at all.
    if (await _hasUserProfile(user.uid)) {
      await refreshLoginAndStreak(user.uid);
    }
  }

  /// Whether [uid] is somebody CheCu knows: a tenant member or a platform
  /// owner.
  Future<bool> _isProvisioned(String uid) async {
    if (await _hasUserProfile(uid)) return true;
    try {
      final owner = await _firestore
          .collection(FirestoreCollections.platformOwners)
          .doc(uid)
          .get();
      return owner.exists;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

  Future<bool> _hasUserProfile(String uid) async {
    try {
      final doc =
          await _firestore.collection(FirestoreCollections.users).doc(uid).get();
      return doc.exists;
    } on FirebaseException catch (e) {
      // `users/{userId}` only grants `get` when the document's empresaId
      // matches the caller's own, so a *missing* document fails the rule
      // rather than coming back empty: the rule dereferences `resource.data`,
      // which does not exist. Firestore reports that as permission-denied,
      // which here means precisely "no profile" — the one case this method
      // exists to detect. Any other failure is a real error and must not be
      // disguised as "your account is not registered".
      if (e.code == 'permission-denied') return false;
      rethrow;
    }
  }

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
    List<String> groupIds = const [],
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
        'groupIds': groupIds,
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

/// Raised when Google authenticated somebody who has no place in CheCu.
///
/// Distinct from any `FirebaseAuthException`: nothing failed on Firebase's
/// side — the sign-in worked perfectly and was then refused by CheCu itself,
/// which is a different thing to tell the user.
class AccountNotProvisionedException implements Exception {
  const AccountNotProvisionedException(this.email);

  /// The address Google returned, so the message can name it — people
  /// routinely pick the wrong account out of the Google chooser.
  final String? email;

  @override
  String toString() => 'AccountNotProvisionedException($email)';
}
