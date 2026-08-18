import 'dart:math' as math;

import 'package:flutter/material.dart';

/// CheCu's symbol — the open circle with the check running out through its
/// gap — drawn as a vector instead of loaded from `logo_checu.png`.
///
/// That PNG is an *app icon*, not a logo: a cream rounded-square tile with the
/// symbol sitting small in the middle of it. It is right for a phone home
/// screen and wrong everywhere else. Clipped into a circular badge it showed
/// its square tile through the round hole, and because the symbol occupies
/// only the centre of the tile it shrank to almost nothing at badge sizes.
///
/// Drawn here it is the symbol alone, with no background of its own, so it
/// sits on whatever surface it is placed on. It is also sharp at any size and
/// costs no download, where the PNG is 838 KB — heavier than it looks, on the
/// very first screen of the app.
///
/// The geometry is Lucide's `circle-check-big` on a 24×24 box, the same
/// drawing the icon was made from. Its `<path>` uses an elliptical arc, which
/// is far more direct to express as [Path.arcTo] than to parse: one circle of
/// radius 10 about the centre, opened between the two endpoints below.
class CheCuMark extends StatelessWidget {
  const CheCuMark({
    super.key,
    this.size = 24,
    required this.color,
    this.strokeWidth = 2,
  });

  final double size;
  final Color color;

  /// On Lucide's 24-unit box, matching the icon's own weight.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CheCuMarkPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

const double _kViewBox = 24;

/// Where the ring opens, as angles about (12, 12) with radius 10 — derived
/// from the two endpoints of Lucide's arc, (21.801, 10) and (17, 3.335).
final double _kArcStart = math.atan2(10 - 12, 21.801 - 12);
final double _kArcEnd = math.atan2(3.335 - 12, 17 - 12);

class _CheCuMarkPainter extends CustomPainter {
  _CheCuMarkPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _kViewBox;
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // The long way round: the gap left open is the small one at the top right,
    // where the check passes through.
    var sweep = _kArcEnd - _kArcStart;
    if (sweep <= 0) sweep += 2 * math.pi;

    canvas.drawPath(
      Path()
        ..arcTo(
          const Rect.fromLTWH(2, 2, 20, 20),
          _kArcStart,
          sweep,
          true,
        ),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(9, 11)
        ..lineTo(12, 14)
        ..lineTo(22, 4),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CheCuMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
