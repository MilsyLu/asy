import 'package:flutter/material.dart';

/// Screen-width thresholds used throughout the responsive layout system.
///
///  < [mobile]               → mobile   (BottomNavigationBar)
///  [mobile] ≤ w < [tablet]  → tablet   (NavigationRail)
///  ≥ [tablet]               → desktop  (permanent NavigationDrawer)
class Breakpoints {
  Breakpoints._();

  static const double mobile = 600;
  static const double tablet = 1024;
}

/// Static helpers for querying the current screen-size class.
///
/// Prefer the [ResponsiveContext] extension (`context.isMobile`) when already
/// inside a `build` method — it reads identically but requires less typing.
class Responsive {
  Responsive._();

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < Breakpoints.mobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= Breakpoints.mobile && w < Breakpoints.tablet;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= Breakpoints.tablet;

  static double screenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  /// Returns [mobile], [tablet] (falls back to [desktop] when omitted), or
  /// [desktop] depending on the current screen width.
  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    if (isDesktop(context)) return desktop;
    if (isTablet(context)) return tablet ?? desktop;
    return mobile;
  }
}

/// Convenience extension — write `context.isMobile` instead of
/// `Responsive.isMobile(context)` inside widget `build` methods.
extension ResponsiveContext on BuildContext {
  bool get isMobile => Responsive.isMobile(this);
  bool get isTablet => Responsive.isTablet(this);
  bool get isDesktop => Responsive.isDesktop(this);
  double get screenWidth => Responsive.screenWidth(this);
  double get screenHeight => Responsive.screenHeight(this);
}
