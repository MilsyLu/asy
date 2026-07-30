import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/user_repository.dart';

/// Tracks the current Firebase Auth user and the matching Firestore
/// `users/{uid}` document, and keeps the FCM token registered while
/// the user is logged in.
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    AuthService? authService,
    UserRepository? userRepository,
  })  : _authService = authService ?? AuthService(),
        _userRepository = userRepository ?? UserRepository() {
    _authSub = _authService.authStateChanges.listen(_onAuthChanged);
    // A session left open across midnight never calls signIn() again (the
    // Firebase Auth token just stays valid), so nothing would otherwise
    // notice the calendar day changed — the streak would stop advancing
    // and any screen showing "today" (Home's header/agenda) would stay
    // stuck on the stale date until a full reload. Checked every minute
    // rather than with a single midnight-timer so it also self-corrects
    // after the device sleeps/wakes or the system clock changes.
    _dayRolloverTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkDayRollover(),
    );
  }

  final AuthService _authService;
  final UserRepository _userRepository;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _userSub;
  Timer? _dayRolloverTimer;

  User? firebaseUser;
  AppUser? appUser;
  bool isLoading = true;

  DateTime _today = _startOfDay(DateTime.now());

  /// Today's date, normalized to midnight — the single source of truth for
  /// any screen that needs "today" (e.g. Home's header/agenda range) so it
  /// rolls over live instead of being captured once via `DateTime.now()`
  /// in a long-lived widget's state.
  DateTime get today => _today;

  static DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

  void _checkDayRollover() {
    final now = _startOfDay(DateTime.now());
    if (now == _today) return;
    _today = now;
    final uid = appUser?.id;
    if (uid != null) {
      _authService.refreshLoginAndStreak(uid).catchError((e) {
        debugPrint('[AuthProvider] Day-rollover streak refresh failed: $e');
      });
    }
    notifyListeners();
  }

  /// Set right before a forced sign-out caused by [AppUser.isActive] being
  /// `false`, so [LoginPage] can show why the session was closed. Cleared
  /// once consumed via [clearDeactivationMessage].
  String? deactivationMessage;

  bool get isAuthenticated => firebaseUser != null;
  bool get isSuperAdmin => appUser?.isSuperAdmin ?? false;
  bool get isScopedAdmin => appUser?.isScopedAdmin ?? false;

  /// True for any kind of administrator (super_admin or admin_equipo) —
  /// use this where a screen/menu should be reachable by either, then gate
  /// individual actions inside with [hasPermission]/[managesGroup].
  bool get isAdminOfAnyKind => isSuperAdmin || isScopedAdmin;

  bool hasPermission(String key) => appUser?.hasPermission(key) ?? false;

  bool managesGroup(String? groupId) =>
      appUser?.managesGroup(groupId) ?? false;

  void _onAuthChanged(User? user) {
    firebaseUser = user;
    _userSub?.cancel();

    if (user == null) {
      appUser = null;
      isLoading = false;
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    _userSub = _userRepository.watchUser(user.uid).listen((profile) async {
      if (profile != null && !profile.isActive) {
        // Set without notifyListeners() so MainShell never gets a chance to
        // render for a deactivated account — signOut() below reads
        // appUser.id for FCM cleanup, then the resulting auth state change
        // (user == null) is what actually triggers the rebuild into LoginPage.
        appUser = profile;
        deactivationMessage =
            'Tu cuenta ha sido desactivada. Contacta a un administrador.';
        await signOut();
        return;
      }
      appUser = profile;
      isLoading = false;
      notifyListeners();
      if (profile != null) {
        _registerFcmToken(profile.id);
      }
    });
  }

  void clearDeactivationMessage() {
    deactivationMessage = null;
  }

  Future<void> _registerFcmToken(String uid) async {
    debugPrint('[WEB_FCM_DIAG] _registerFcmToken() ENTRY uid=$uid');
    try {
      debugPrint('[WEB_FCM_DIAG] _registerFcmToken(): calling getToken()...');
      final token = await NotificationService.instance.getToken();
      debugPrint(
        '[WEB_FCM_DIAG] _registerFcmToken(): getToken() returned '
        '${token == null ? "NULL — addFcmToken() will NOT be called" : "token(len=${token.length}) — calling addFcmToken()"}',
      );
      if (token != null) {
        await _userRepository.addFcmToken(uid, token);
        debugPrint('[WEB_FCM_DIAG] _registerFcmToken(): addFcmToken() returned');
      }
      // Sprint 7.4.3 Parte 1: this only swaps the handler reference — the
      // underlying `onTokenRefresh` subscription is created exactly once,
      // inside NotificationService.initialize(). Re-running this method on
      // every `users/{uid}` snapshot (not just login) no longer accumulates
      // a new listener each time.
      NotificationService.instance.setTokenRefreshHandler((newToken) {
        debugPrint('[WEB_FCM_DIAG] onTokenRefresh: new token (len=${newToken.length}), calling addFcmToken(uid=$uid)');
        _userRepository.addFcmToken(uid, newToken);
      });
    } catch (e, st) {
      debugPrint(
        '[WEB_FCM_DIAG] _registerFcmToken() CAUGHT EXCEPTION\n'
        '  runtimeType: ${e.runtimeType}\n'
        '  toString: $e',
      );
      if (e is FirebaseException) {
        debugPrint(
          '[WEB_FCM_DIAG] FirebaseException:\n'
          '  plugin: ${e.plugin}\n'
          '  code: ${e.code}\n'
          '  message: ${e.message}\n'
          '  stackTrace: ${e.stackTrace}',
        );
      }
      if (e is PlatformException) {
        debugPrint(
          '[WEB_FCM_DIAG] PlatformException:\n'
          '  code: ${e.code}\n'
          '  message: ${e.message}\n'
          '  details: ${e.details}\n'
          '  stacktrace: ${e.stacktrace}',
        );
      }
      debugPrint('[WEB_FCM_DIAG] _registerFcmToken() stackTrace:\n$st');
    }
  }

  Future<void> signIn(String email, String password) {
    return _authService.signIn(email: email, password: password);
  }

  Future<void> sendPasswordReset(String email) {
    return _authService.sendPasswordResetEmail(email);
  }

  Future<void> signOut() async {
    final uid = appUser?.id;
    if (uid != null) {
      try {
        final token = await NotificationService.instance.getToken();
        if (token != null) {
          await _userRepository.removeFcmToken(uid, token);
        }
      } catch (e) {
        debugPrint('FCM token cleanup skipped: $e');
      }
    }
    // Sprint 7.4.3 Parte 1: clear the handler so a token rotation that
    // fires after this point doesn't write to the now-logged-out uid.
    NotificationService.instance.setTokenRefreshHandler(null);
    await _authService.signOut();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    _dayRolloverTimer?.cancel();
    super.dispose();
  }
}
