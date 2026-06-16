import 'package:flutter/material.dart';

import '../core/theme/theme_colors.dart';
import '../models/app_user.dart';

/// Circular avatar that shows [user.photoUrl] if available, otherwise the
/// user's initials on a semi-transparent primary background.
///
/// Pure display widget — gestures are wired by the caller.
class UserAvatarDisplay extends StatelessWidget {
  const UserAvatarDisplay({
    super.key,
    required this.user,
    this.size = 72.0,
    this.borderWidth = 2.0,
  });

  final AppUser user;
  final double size;
  final double borderWidth;

  String get _initials {
    final parts = user.name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final photoUrl = user.photoUrl;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.primary, width: borderWidth),
      ),
      child: ClipOval(
        child: photoUrl != null && photoUrl.isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _InitialsCircle(
                  initials: _initials,
                  colors: colors,
                  size: size,
                ),
              )
            : _InitialsCircle(
                initials: _initials,
                colors: colors,
                size: size,
              ),
      ),
    );
  }
}

class _InitialsCircle extends StatelessWidget {
  const _InitialsCircle({
    required this.initials,
    required this.colors,
    required this.size,
  });

  final String initials;
  final AppColorsExtension colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.primary.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: colors.primary,
          fontSize: size * 0.3,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
