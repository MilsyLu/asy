import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/responsive/app_spacing.dart';
import '../core/responsive/responsive.dart';
import '../core/theme/theme_colors.dart';
import '../services/app_update_service.dart';

/// Animated banner that appears at the top of [MainShell] when a new version
/// of CheCu is available. Fades + slides in/out via [AnimatedSwitcher].
///
/// - Desktop/tablet: horizontal row (icon · message · button · close).
/// - Mobile:         stacked column (icon + message / button / close icon).
///
/// The user always initiates the update — the page is never reloaded
/// automatically, so no in-progress work is lost.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _isUpdating = false;

  Future<void> _onUpdate(AppUpdateService service) async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    await service.activateUpdate();
    if (mounted) setState(() => _isUpdating = false);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppUpdateService>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(sizeFactor: anim, axisAlignment: -1, child: child),
      ),
      child: service.showBanner
          ? _BannerBody(
              key: const ValueKey('update-banner'),
              version: service.remoteVersion,
              isUpdating: _isUpdating,
              onUpdate: () => _onUpdate(service),
              onDismiss: service.dismiss,
            )
          : const SizedBox.shrink(key: ValueKey('update-banner-hidden')),
    );
  }
}

// ── Banner content ────────────────────────────────────────────────────────────

class _BannerBody extends StatelessWidget {
  const _BannerBody({
    super.key,
    this.version,
    required this.isUpdating,
    required this.onUpdate,
    required this.onDismiss,
  });

  final String? version;
  final bool isUpdating;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMobile = context.isMobile;
    final versionStr = version != null ? ' (v$version)' : '';

    return Semantics(
      liveRegion: true,
      label: 'Nueva versión disponible$versionStr. '
          'Pulsa Actualizar ahora para aplicar los cambios.',
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? AppSpacing.md : AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colors.primary.withValues(alpha: 0.18),
              colors.primary.withValues(alpha: 0.10),
            ],
          ),
          border: Border(
            bottom: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
          ),
        ),
        child: isMobile
            ? _MobileLayout(
                versionStr: versionStr,
                isUpdating: isUpdating,
                onUpdate: onUpdate,
                onDismiss: onDismiss,
                colors: colors,
              )
            : _DesktopLayout(
                versionStr: versionStr,
                isUpdating: isUpdating,
                onUpdate: onUpdate,
                onDismiss: onDismiss,
                colors: colors,
              ),
      ),
    );
  }
}

// ── Desktop / tablet ──────────────────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.versionStr,
    required this.isUpdating,
    required this.onUpdate,
    required this.onDismiss,
    required this.colors,
  });

  final String versionStr;
  final bool isUpdating;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(LucideIcons.refreshCw, size: 14, color: colors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Nueva versión disponible$versionStr',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Se han aplicado mejoras y correcciones.',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _UpdateButton(
            isUpdating: isUpdating, onUpdate: onUpdate, colors: colors),
        const SizedBox(width: AppSpacing.sm),
        _DismissButton(onDismiss: onDismiss, colors: colors),
      ],
    );
  }
}

// ── Mobile ────────────────────────────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.versionStr,
    required this.isUpdating,
    required this.onUpdate,
    required this.onDismiss,
    required this.colors,
  });

  final String versionStr;
  final bool isUpdating;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(LucideIcons.refreshCw, size: 13, color: colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Nueva versión disponible$versionStr',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _DismissButton(onDismiss: onDismiss, colors: colors),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Se han aplicado mejoras y correcciones.',
          style: TextStyle(color: colors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: AppSpacing.sm),
        _UpdateButton(
          isUpdating: isUpdating,
          onUpdate: onUpdate,
          colors: colors,
          fullWidth: true,
        ),
      ],
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _UpdateButton extends StatelessWidget {
  const _UpdateButton({
    required this.isUpdating,
    required this.onUpdate,
    required this.colors,
    this.fullWidth = false,
  });

  final bool isUpdating;
  final VoidCallback onUpdate;
  final AppColorsExtension colors;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final btn = FilledButton.icon(
      onPressed: isUpdating ? null : onUpdate,
      icon: isUpdating
          ? SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.background,
              ),
            )
          : const Icon(LucideIcons.refreshCw, size: 13),
      label: Text(
        isUpdating ? 'Actualizando…' : 'Actualizar ahora',
        style: const TextStyle(fontSize: 12),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.background,
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onDismiss, required this.colors});

  final VoidCallback onDismiss;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cerrar aviso de actualización',
      child: IconButton(
        onPressed: onDismiss,
        icon: Icon(LucideIcons.x, size: 14, color: colors.textSecondary),
        tooltip: 'Cerrar',
        style: IconButton.styleFrom(
          minimumSize: const Size(28, 28),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
