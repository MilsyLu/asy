// Spacing scale and layout dimension constants.
// Use these instead of inline numeric literals to keep measurements
// consistent and easy to adjust as the responsive sprints progress.

/// Spacing scale, page padding, and border-radius values.
class AppSpacing {
  AppSpacing._();

  // ── Spacing scale ────────────────────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  // ── Page padding (horizontal) ────────────────────────────────────────────
  static const double pagePaddingMobile = 16;
  static const double pagePaddingTablet = 24;
  static const double pagePaddingDesktop = 32;

  // ── Border radius ────────────────────────────────────────────────────────
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;

  // ── Card ─────────────────────────────────────────────────────────────────
  static const double cardSpacing = 12;
}

/// Layout dimension constants: max content widths, navigation, dialogs.
class AppLayout {
  AppLayout._();

  // ── Max content widths ───────────────────────────────────────────────────
  /// Narrow forms (login, forgot-password, single-field dialogs).
  static const double contentMaxWidthNarrow = 420;

  /// Single-column content pages (profile, settings).
  static const double contentMaxWidthMedium = 600;

  /// Two-column or card-grid content.
  static const double contentMaxWidthWide = 960;

  /// Full-bleed desktop container.
  static const double contentMaxWidthFull = 1280;

  // ── Navigation ───────────────────────────────────────────────────────────
  static const double navigationRailWidth = 72;
  static const double navigationDrawerWidth = 256;

  // ── Dialogs ──────────────────────────────────────────────────────────────
  static const double dialogWidthTablet = 520;
  static const double dialogWidthDesktop = 560;

  // ── Bars ─────────────────────────────────────────────────────────────────
  static const double appBarHeight = 56;
  static const double bottomNavHeight = 56;
}
