import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/app_user.dart';
import '../../services/user_repository.dart';
import 'app_theme.dart';
import 'theme_colors.dart';
import 'theme_preferences_cache.dart';

/// Single source of truth for the app's visual personalization (FASE 1-3).
///
/// Holds the active [ThemeMode] (system/light/dark) and [AppAccentColor]
/// (gold/blue/green/purple), exposes the matching [lightTheme]/[darkTheme]
/// for [MaterialApp], and persists per-user choices to Firestore
/// (`users/{uid}.themeMode` / `.accentColor`) — the source of truth across
/// devices — while mirroring them to a local [ThemePreferencesCache] so the
/// app can apply the last-known preferences instantly on the next launch,
/// before the Firestore document has loaded. Defaults to dark mode + the
/// gold accent, matching the app's original always-dark theme.
class ThemeManager extends ChangeNotifier {
  ThemeManager({UserRepository? userRepository, ThemePreferencesCache? cache})
      : _userRepository = userRepository ?? UserRepository(),
        _cache = cache ?? ThemePreferencesCache() {
    unawaited(loadCachedPreferences());
  }

  final UserRepository _userRepository;
  final ThemePreferencesCache _cache;

  ThemeMode _themeMode = ThemeMode.dark;
  AppAccentColor _accentColor = AppAccentColor.gold;
  String? _userId;

  ThemeMode get themeMode => _themeMode;
  AppAccentColor get accentColor => _accentColor;

  ThemeData get lightTheme =>
      AppTheme.themeFor(_accentColor, Brightness.light);
  ThemeData get darkTheme => AppTheme.themeFor(_accentColor, Brightness.dark);

  /// Loads the last-known preferences from the local [ThemePreferencesCache]
  /// (FASE 3 startup cache). Called once on construction so the app applies
  /// them immediately, before Firestore data is available. A no-op if
  /// nothing is cached yet, since the cached defaults match [_themeMode]/
  /// [_accentColor]'s initial values.
  Future<void> loadCachedPreferences() async {
    final (mode, accent) = await _cache.read();
    final resolvedMode = themeModeFromStorage(mode);
    final resolvedAccent = AppAccentColor.fromStorage(accent);

    if (resolvedMode != _themeMode || resolvedAccent != _accentColor) {
      _themeMode = resolvedMode;
      _accentColor = resolvedAccent;
      notifyListeners();
    }
  }

  /// Syncs local state from the signed-in user's stored preferences.
  /// Called whenever `AuthProvider.appUser` changes (login, logout, user
  /// switch, or a Firestore update to the user's own preferences).
  ///
  /// Firestore is the source of truth: when it disagrees with the local
  /// cache (e.g. the preference changed on another device), the local
  /// state and cache are updated to match.
  void updateFromUser(AppUser? user) {
    if (user == null) {
      _userId = null;
      return;
    }

    final userChanged = _userId != user.id;
    final mode = themeModeFromStorage(user.themeMode);
    final accent = AppAccentColor.fromStorage(user.accentColor);
    _userId = user.id;

    if (userChanged || mode != _themeMode || accent != _accentColor) {
      _themeMode = mode;
      _accentColor = accent;
      notifyListeners();
      unawaited(_cache.save(
        themeMode: themeModeToStorage(mode),
        accentColor: accent.storageValue,
      ));
    }
  }

  /// Updates the appearance mode immediately, mirrors it to the local
  /// startup cache, and persists it for the signed-in user in Firestore.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    unawaited(_cache.save(
      themeMode: themeModeToStorage(mode),
      accentColor: _accentColor.storageValue,
    ));
    final uid = _userId;
    if (uid != null) {
      await _userRepository.updateThemePreferences(
        uid,
        themeMode: themeModeToStorage(mode),
      );
    }
  }

  /// Updates the accent color immediately, mirrors it to the local startup
  /// cache, and persists it for the signed-in user in Firestore.
  Future<void> setAccentColor(AppAccentColor accent) async {
    if (_accentColor == accent) return;
    _accentColor = accent;
    notifyListeners();
    unawaited(_cache.save(
      themeMode: themeModeToStorage(_themeMode),
      accentColor: accent.storageValue,
    ));
    final uid = _userId;
    if (uid != null) {
      await _userRepository.updateThemePreferences(
        uid,
        accentColor: accent.storageValue,
      );
    }
  }
}

/// Parses a `users/{uid}.themeMode` value ('system' | 'light' | 'dark'),
/// defaulting to [ThemeMode.dark] for legacy/unknown values — matching the
/// app's original always-dark theme for users who haven't set a preference.
ThemeMode themeModeFromStorage(String? value) {
  switch (value) {
    case 'system':
      return ThemeMode.system;
    case 'light':
      return ThemeMode.light;
    default:
      return ThemeMode.dark;
  }
}

/// Serializes a [ThemeMode] for storage in `users/{uid}.themeMode`.
String themeModeToStorage(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}
