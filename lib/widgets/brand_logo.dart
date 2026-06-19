import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

/// CheCu's circular logo badge: the official `logo_checu.png` framed in the
/// same bordered-circle treatment originally built for the Login screen
/// (Sprint 7.3.2A/C). Shared by Login and the app boot splash so both use
/// the exact same construction instead of duplicating it or, on the splash
/// side, rendering the raw asset unframed.
///
/// Fixed institutional colors regardless of theme/user, matching the screens
/// that use it.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 84});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppConstants.brandPrimary, width: 2),
      ),
      child: ClipOval(
        child: Padding(
          padding: EdgeInsets.all(size * 0.1),
          child: Image.asset('assets/branding/logo_checu.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}
