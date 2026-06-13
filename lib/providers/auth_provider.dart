import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  }

  final AuthService _authService;
  final UserRepository _userRepository;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _userSub;

  User? firebaseUser;
  AppUser? appUser;
  bool isLoading = true;

  bool get isAuthenticated => firebaseUser != null;
  bool get isSuperAdmin => appUser?.isSuperAdmin ?? false;

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

    _userSub = _userRepository.watchUser(user.uid).listen((profile) {
      appUser = profile;
      isLoading = false;
      notifyListeners();
      if (profile != null) {
        _registerFcmToken(profile.id);
      }
    });
  }

  Future<void> _registerFcmToken(String uid) async {
    try {
      final token = await NotificationService.instance.getToken();
      if (token != null) {
        await _userRepository.addFcmToken(uid, token);
      }
      NotificationService.instance.onTokenRefresh((newToken) {
        _userRepository.addFcmToken(uid, newToken);
      });
    } catch (e) {
      debugPrint('FCM token registration skipped: $e');
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
    await _authService.signOut();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }
}
