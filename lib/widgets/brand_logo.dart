import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import 'checu_mark.dart';

/// CheCu's circular logo badge: the symbol inside the bordered-circle
/// treatment originally built for the Login screen (Sprint 7.3.2A/C). Shared
/// by Login, the app boot splash and the shell header so they all use the
/// exact same construction instead of duplicating it.
///
/// The symbol is drawn by [CheCuMark] rather than loaded from
/// `logo_checu.png`. That file is the app-launcher icon — the symbol printed
/// small on a cream rounded-square tile — so clipping it into this circle put
/// a square inside a round hole, with the symbol itself far too small to read
/// at badge sizes. The border below stands in for the outer ring the icon
/// draws inside its tile, so the badge still reads as the same logo.
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
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppConstants.brandPrimary,
          // Scales with the badge: a fixed 2px hairline looks heavy at 32 and
          // spindly at 96, and this is used at both.
          width: (size * 0.025).clamp(1.0, 2.5),
        ),
      ),
      // Half the badge — the proportion the symbol has to the ring drawn
      // around it in the source artwork.
      child: CheCuMark(size: size * 0.5, color: AppConstants.brandPrimary),
    );
  }
}
