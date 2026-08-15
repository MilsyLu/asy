import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/empresa_model.dart';
import '../services/auth_service.dart';
import '../services/empresa_repository.dart';
import '../services/notification_service.dart';
import '../services/user_repository.dart';

/// Tracks the current Firebase Auth user and the matching Firestore
/// `users/{uid}` document, and keeps the FCM token registered while
/// the user is logged in.
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    AuthService? authService,
    UserRepository? userRepository,
    EmpresaRepository? empresaRepository,
  })  : _authService = authService ?? AuthService(),
        _userRepository = userRepository ?? UserRepository(),
        _empresaRepository = empresaRepository ?? EmpresaRepository() {
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
  final EmpresaRepository _empresaRepository;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _userSub;
  StreamSubscription<EmpresaModel?>? _empresaSub;

  /// Guards against re-running per-user setup on every profile snapshot —
  /// see the comments at their call sites in [_onAuthChanged].
  String? _fcmRegisteredForUid;
  String? _watchedEmpresaId;
  Timer? _dayRolloverTimer;

  User? firebaseUser;
  AppUser? appUser;
  bool isLoading = true;

  /// True if the signed-in Firebase Auth account is a platform owner
  /// (Michel) — a completely separate identity from any empresa's own
  /// super_admin, checked once per sign-in via `platformOwners/{uid}` (see
  /// [EmpresaRepository.isPlatformOwner]). When true, [appUser] is
  /// deliberately left null and no tenant-scoped subscription is ever
  /// started — see `AuthGate` in `app.dart`, which routes a platform owner
  /// straight to `PlatformAdminShell` instead of `MainShell`.
  bool isPlatformOwner = false;

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

  void _onAuthChanged(User? user) async {
    firebaseUser = user;
    _userSub?.cancel();
    _empresaSub?.cancel();
    // Reset the once-per-user guards along with the subscriptions they pair
    // with, so signing in as somebody else re-registers their token and
    // re-watches their empresa instead of inheriting the previous session's.
    _empresaSub = null;
    _fcmRegisteredForUid = null;
    _watchedEmpresaId = null;

    if (user == null) {
      appUser = null;
      isPlatformOwner = false;
      isLoading = false;
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    // Checked first, before any tenant-scoped subscription starts — a
    // platform owner (Michel) never has (and never needs) a `users/{uid}`
    // profile of their own. This is a one-time check, not a live watch:
    // platform-owner status essentially never changes for an already-open
    // session, so it's not worth the extra always-on listener.
    final owner = await _empresaRepository.isPlatformOwner(user.uid);
    if (owner) {
      isPlatformOwner = true;
      appUser = null;
      isLoading = false;
      notifyListeners();
      return;
    }
    isPlatformOwner = false;

    // A session restored from an already-valid Firebase Auth token (the
    // common case: closing the tab/browser and reopening it the next day)
    // never goes through AuthService.signIn() — only an explicit
    // email/password login does. Without this call, lastLogin/streakDays
    // only ever updated while the app happened to stay open across a real
    // midnight rollover (see _checkDayRollover below), never on the
    // ordinary "open the app fresh the next day" flow — which is exactly
    // what silently froze Michel's streak. Safe to call unconditionally
    // here: it's a no-op for lastLogin/streak beyond bumping the timestamp
    // if it's already been refreshed today (day-diff logic, not call-count
    // based), and this only runs once per auth-state change, not on every
    // watchUser() snapshot below.
    _authService.refreshLoginAndStreak(user.uid).catchError((e) {
      debugPrint('[AuthProvider] Session-restore streak refresh failed: $e');
    });

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
        // Both of these used to run on *every* `users/{uid}` snapshot, which
        // was self-sustaining work: registering the token queries Firestore
        // and opens a transaction, and when that transaction writes, the
        // write produces another snapshot, which registers again. Even the
        // no-op path (token already stored) cost a getToken() call, a query
        // and a transaction per snapshot, and re-created the empresa listener
        // from scratch each time. Both are per-user facts, so they now run
        // once per signed-in user; token rotation is already covered
        // separately by the permanent onTokenRefresh subscription installed
        // inside _registerFcmToken.
        if (_fcmRegisteredForUid != profile.id) {
          _fcmRegisteredForUid = profile.id;
          _registerFcmToken(profile.id, profile.empresaId, profile.fcmTokens);
        }
        _watchEmpresaStatus(profile.empresaId);
      }
    });
  }

  /// Mirrors the individual-account force-signout above, one level up: if
  /// the signed-in user's own empresa is deactivated (e.g. Michel cuts off
  /// a customer for non-payment) while their session is open, they're
  /// signed out immediately with a clear reason instead of silently hitting
  /// permission-denied errors on their next Firestore call.
  void _watchEmpresaStatus(String? empresaId) {
    // Called on every user-doc snapshot, but the empresa a user belongs to
    // essentially never changes mid-session — so re-subscribing each time
    // just tore down a healthy Firestore listener and paid for a fresh
    // initial snapshot, over and over.
    if (empresaId == _watchedEmpresaId && _empresaSub != null) return;
    _watchedEmpresaId = empresaId;
    _empresaSub?.cancel();
    _empresaSub = null;
    if (empresaId == null) return;
    _empresaSub = _empresaRepository.watchEmpresa(empresaId).listen((empresa) async {
      if (empresa != null && !empresa.activo) {
        deactivationMessage =
            'Tu empresa ha sido desactivada. Contacta al administrador de la plataforma.';
        await signOut();
      }
    });
  }

  void clearDeactivationMessage() {
    deactivationMessage = null;
  }

  /// Key under which the last token this device successfully registered is
  /// remembered, so [_registerFcmToken] can recognise a token the server has
  /// since rejected. Scoped per user: two accounts on one browser each get
  /// their own record.
  static String _lastTokenKey(String uid) => 'fcm_last_registered_token_$uid';

  Future<void> _registerFcmToken(
    String uid,
    String? empresaId,
    List<String> knownTokens,
  ) async {
    debugPrint('[WEB_FCM_DIAG] _registerFcmToken() ENTRY uid=$uid');
    try {
      debugPrint('[WEB_FCM_DIAG] _registerFcmToken(): calling getToken()...');
      var token = await NotificationService.instance.getToken();
      debugPrint(
        '[WEB_FCM_DIAG] _registerFcmToken(): getToken() returned '
        '${token == null ? "NULL — addFcmToken() will NOT be called" : "token(len=${token.length}) — calling addFcmToken()"}',
      );

      // Self-healing for a dead push subscription.
      //
      // When a subscription dies, FCM answers registration-token-not-registered
      // and the server drops that token from the profile — but getToken() keeps
      // returning the very same string from its IndexedDB cache, so the client
      // re-registers the identical dead token and the pair loops forever, with
      // the device looking correctly registered while receiving nothing.
      //
      // The giveaway is precise: the token is missing from the profile *and*
      // this device remembers having registered exactly it. A device that
      // simply never registered before is also missing from the profile, which
      // is why the remembered value — not the absence alone — is what triggers
      // the reset. deleteToken() is the only thing that makes the next
      // getToken() mint a genuinely new subscription.
      final prefs = await SharedPreferences.getInstance();
      final rememberedToken = prefs.getString(_lastTokenKey(uid));
      if (token != null &&
          !knownTokens.contains(token) &&
          rememberedToken == token) {
        debugPrint(
          '[WEB_FCM_DIAG] _registerFcmToken(): token registrado antes pero '
          'ausente del perfil — el servidor lo rechazo. Renovando.',
        );
        await NotificationService.instance.deleteToken();
        token = await NotificationService.instance.getToken();
        debugPrint(
          '[WEB_FCM_DIAG] _registerFcmToken(): token renovado '
          '${token == null ? "NULL" : "(len=${token.length})"}',
        );
      }

      if (token != null) {
        await _userRepository.addFcmToken(uid, token, callerEmpresaId: empresaId);
        await prefs.setString(_lastTokenKey(uid), token);
        debugPrint('[WEB_FCM_DIAG] _registerFcmToken(): addFcmToken() returned');
      }
      // Sprint 7.4.3 Parte 1: this only swaps the handler reference — the
      // underlying `onTokenRefresh` subscription is created exactly once,
      // inside NotificationService.initialize(). Re-running this method on
      // every `users/{uid}` snapshot (not just login) no longer accumulates
      // a new listener each time.
      NotificationService.instance.setTokenRefreshHandler((newToken) async {
        debugPrint('[WEB_FCM_DIAG] onTokenRefresh: new token (len=${newToken.length}), calling addFcmToken(uid=$uid)');
        await _userRepository.addFcmToken(uid, newToken, callerEmpresaId: empresaId);
        // Keep the remembered value in step with what is actually registered,
        // or the next startup would compare against a stale token and either
        // heal when it shouldn't or miss a real rejection.
        await (await SharedPreferences.getInstance())
            .setString(_lastTokenKey(uid), newToken);
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
    _empresaSub?.cancel();
    _dayRolloverTimer?.cancel();
    super.dispose();
  }
}
