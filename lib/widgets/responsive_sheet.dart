import 'package:flutter/material.dart';

import '../core/responsive/app_spacing.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/theme_colors.dart';

/// Shows [contentBuilder] as a bottom sheet on mobile (the existing pattern,
/// unchanged) or as a centered, floating, scrollable dialog on tablet/
/// desktop — generalizes the pattern `profile_page.dart`'s `_showPhotoOptions`
/// already used by hand for "sheets shouldn't be pinned to the bottom of a
/// tall desktop viewport."
///
/// [contentBuilder] is passed straight through as the mobile sheet's
/// `builder` — on mobile this call is a drop-in replacement for a bare
/// `showModalBottomSheet` call, so existing content (its own internal
/// `SafeArea`/`Padding`/grabber) renders pixel-identical to before. On
/// tablet/desktop that same content is reused inside a centered `Dialog`
/// instead — no separate desktop-only content needed.
Future<T?> showResponsiveSheet<T>(
  BuildContext context, {
  required WidgetBuilder contentBuilder,
  double desktopMaxWidth = AppLayout.dialogWidthDesktop,
  bool scrollable = true,
}) {
  final colors = context.colors;

  if (context.isMobile) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: contentBuilder,
    );
  }

  return showDialog<T>(
    context: context,
    builder: (dialogContext) {
      final content = contentBuilder(dialogContext);
      return Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: desktopMaxWidth,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
          ),
          child: scrollable ? SingleChildScrollView(child: content) : content,
        ),
      );
    },
  );
}
