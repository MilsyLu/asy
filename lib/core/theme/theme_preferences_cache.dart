import 'package:shared_preferences/shared_preferences.dart';

/// Local startup cache for visual preferences (FASE 3).
///
/// This is **not** the source of truth — `users/{uid}.themeMode` /
/// `.accentColor` in Firestore is — but lets [ThemeManager] apply the
/// last-known `themeMode`/`accentColor` immediately when the app launches,
/// before the signed-in user's Firestore document has loaded.
class ThemePreferencesCache {
  static const _themeModeKey = 'theme_mode';
  static const _accentColorKey = 'accent_color';

  /// Reads the cached `(themeMode, accentColor)` storage values. Either (or
  /// both) may be `null` if nothing has been cached yet.
  Future<(String?, String?)> read() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_themeModeKey), prefs.getString(_accentColorKey));
  }

  /// Writes the given storage values to the local cache.
  Future<void> save({
    required String themeMode,
    required String accentColor,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, themeMode);
    await prefs.setString(_accentColorKey, accentColor);
  }
}
