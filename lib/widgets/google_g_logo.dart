import 'package:flutter/material.dart';

/// Google's four-colour "G", drawn from its official vector outlines.
///
/// The mark is trademarked and Google's brand guidelines require the real
/// thing on a sign-in button, so approximating it with four coloured arcs was
/// not an option — a hand-tuned lookalike is both off-brand and obviously
/// homemade at the size it is shown here.
///
/// The alternative was pulling in an SVG rendering package for one 18px icon.
/// Instead the four official outlines are kept verbatim below and walked by a
/// small parser covering exactly the commands they use. Keeping the path data
/// in its original form is deliberate: it can be compared character for
/// character against the published asset, which a screenful of generated
/// `cubicTo` calls could not.
///
/// Nothing else in the app needs this, so the parser stays private here.
class GoogleGLogo extends StatelessWidget {
  const GoogleGLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

/// The official outlines, on Google's 24×24 viewBox.
const List<(String, Color)> _kOutlines = [
  (
    'M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 '
        '3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z',
    Color(0xFF4285F4),
  ),
  (
    'M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 '
        '1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z',
    Color(0xFF34A853),
  ),
  (
    'M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 '
        '8.55 1 10.22 1 12s.43 3.45 1.18 4.94l2.85-2.22.81-.63z',
    Color(0xFFFBBC05),
  ),
  (
    'M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 '
        '3.99 3.47 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z',
    Color(0xFFEA4335),
  ),
];

const double _kViewBox = 24;

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _kViewBox, size.height / _kViewBox);
    for (final (data, color) in _kOutlines) {
      canvas.drawPath(
        _parseSvgPath(data),
        Paint()
          ..color = color
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleGPainter oldDelegate) => false;
}

/// Splits an SVG path into its commands and the numbers that follow each one.
final RegExp _kCommand = RegExp(r'([MmLlHhVvCcSsZz])([^MmLlHhVvCcSsZz]*)');

/// SVG allows numbers to run together when the sign separates them
/// (`0-.78`), and to drop the leading zero (`.07`), so they cannot simply be
/// split on whitespace.
final RegExp _kNumber = RegExp(r'-?\d*\.?\d+(?:[eE][-+]?\d+)?');

/// Builds a [Path] from the subset of SVG path syntax the outlines above use:
/// move, line, horizontal, vertical, cubic, smooth cubic and close, in both
/// absolute and relative form. Elliptical arcs (`A`) and quadratics (`Q`) do
/// not appear in them and are not handled.
Path _parseSvgPath(String data) {
  final path = Path();
  var current = Offset.zero;
  var start = Offset.zero;
  // Reflection point for a smooth cubic: the previous curve's second control
  // point. Reset by any command that is not itself a cubic, per the spec.
  Offset? previousControl;

  for (final match in _kCommand.allMatches(data)) {
    final command = match.group(1)!;
    final numbers = _kNumber
        .allMatches(match.group(2)!)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    final relative = command == command.toLowerCase();
    var i = 0;

    Offset point(double x, double y) =>
        relative ? Offset(current.dx + x, current.dy + y) : Offset(x, y);

    switch (command.toUpperCase()) {
      case 'M':
        // Extra coordinate pairs after a moveto are implicit linetos.
        var first = true;
        while (i + 1 < numbers.length) {
          final target = point(numbers[i], numbers[i + 1]);
          if (first) {
            path.moveTo(target.dx, target.dy);
            start = target;
            first = false;
          } else {
            path.lineTo(target.dx, target.dy);
          }
          current = target;
          i += 2;
        }
        previousControl = null;
      case 'L':
        while (i + 1 < numbers.length) {
          current = point(numbers[i], numbers[i + 1]);
          path.lineTo(current.dx, current.dy);
          i += 2;
        }
        previousControl = null;
      case 'H':
        while (i < numbers.length) {
          current = Offset(
            relative ? current.dx + numbers[i] : numbers[i],
            current.dy,
          );
          path.lineTo(current.dx, current.dy);
          i += 1;
        }
        previousControl = null;
      case 'V':
        while (i < numbers.length) {
          current = Offset(
            current.dx,
            relative ? current.dy + numbers[i] : numbers[i],
          );
          path.lineTo(current.dx, current.dy);
          i += 1;
        }
        previousControl = null;
      case 'C':
        while (i + 5 < numbers.length) {
          final c1 = point(numbers[i], numbers[i + 1]);
          final c2 = point(numbers[i + 2], numbers[i + 3]);
          final end = point(numbers[i + 4], numbers[i + 5]);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
          previousControl = c2;
          current = end;
          i += 6;
        }
      case 'S':
        while (i + 3 < numbers.length) {
          // The first control point mirrors the previous one about the
          // current point; with no previous curve it coincides with it.
          final c1 = previousControl == null
              ? current
              : Offset(
                  2 * current.dx - previousControl.dx,
                  2 * current.dy - previousControl.dy,
                );
          final c2 = point(numbers[i], numbers[i + 1]);
          final end = point(numbers[i + 2], numbers[i + 3]);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
          previousControl = c2;
          current = end;
          i += 4;
        }
      case 'Z':
        path.close();
        current = start;
        previousControl = null;
    }
  }
  return path;
}
