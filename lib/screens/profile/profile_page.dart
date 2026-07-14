import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/responsive/app_spacing.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/snackbar_utils.dart';
import '../../models/app_user.dart';
import '../../models/task_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../services/auth_service.dart';
import '../../services/storage_service.dart';
import '../../services/task_repository.dart';
import '../../services/user_repository.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/user_avatar.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _uploading = false;
  Stream<List<TaskModel>>? _thirtyDayStream;
  Stream<List<TaskModel>>? _ninetyDayStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_thirtyDayStream == null) {
      final repo = context.read<TaskRepository>();
      final now = DateTime.now();
      _thirtyDayStream =
          repo.watchTasksInRange(now.subtract(const Duration(days: 30)), now);
      _ninetyDayStream =
          repo.watchTasksInRange(now.subtract(const Duration(days: 90)), now);
    }
  }

  String _streakMessage(int days) {
    if (days == 0) return '¡Comienza hoy!';
    if (days <= 3) return '¡Buen comienzo!';
    if (days <= 6) return '¡Vas muy bien!';
    if (days <= 13) return '¡Una semana seguida!';
    if (days <= 29) return '¡Sigue así!';
    return '¡Increíble constancia!';
  }

  // 7-element bool list (index 0=Mon … 6=Sun): true when a weekday of the
  // current week falls inside the active streak window.
  List<bool> _weekHighlights(int streakDays) {
    final today = DateTime.now();
    final result = List.filled(7, false);
    for (var i = 0; i < 7; i++) {
      // today.weekday: 1=Mon … 7=Sun
      final daysAgo = today.weekday - (i + 1);
      if (daysAgo < 0 || daysAgo >= streakDays) continue;
      result[i] = true;
    }
    return result;
  }

  Future<void> _showPhotoOptions(AppUser user) async {
    final colors = context.colors;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Foto de perfil',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const Divider(),
              if (!kIsWeb)
                ListTile(
                  leading: Icon(LucideIcons.camera, color: colors.primary),
                  title: const Text('Tomar foto'),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _pickPhoto(ImageSource.camera, user.id);
                  },
                ),
              ListTile(
                leading: Icon(LucideIcons.image, color: colors.primary),
                title: const Text('Elegir de galería'),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _pickPhoto(ImageSource.gallery, user.id);
                },
              ),
              if (user.photoUrl != null && user.photoUrl!.isNotEmpty)
                ListTile(
                  leading: Icon(LucideIcons.trash2, color: colors.error),
                  title: Text(
                    'Eliminar foto',
                    style: TextStyle(color: colors.error),
                  ),
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    _deletePhoto(user.id);
                  },
                ),
              ListTile(
                leading: Icon(LucideIcons.x, color: colors.textSecondary),
                title: const Text('Cancelar'),
                onTap: () => Navigator.of(sheetCtx).pop(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickPhoto(ImageSource source, String uid) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      final url = await StorageService.uploadProfilePhoto(uid, bytes);
      if (!mounted) return;
      await context.read<UserRepository>().updatePhotoUrl(uid, url);
      if (mounted) SnackbarUtils.showSuccess(context, 'Foto actualizada');
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'Error al subir la foto');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deletePhoto(String uid) async {
    try {
      setState(() => _uploading = true);
      await StorageService.deleteProfilePhoto(uid);
      if (!mounted) return;
      await context.read<UserRepository>().updatePhotoUrl(uid, null);
      if (mounted) SnackbarUtils.showSuccess(context, 'Foto eliminada');
    } catch (_) {
      if (mounted) SnackbarUtils.showError(context, 'Error al eliminar la foto');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final catalog = context.watch<CatalogProvider>();
    final user = auth.appUser;
    final colors = context.colors;

    if (user == null) {
      return const Scaffold(body: LoadingIndicator());
    }

    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;
    final hPad = isDesktop
        ? AppSpacing.pagePaddingDesktop
        : isTablet
            ? AppSpacing.pagePaddingTablet
            : AppSpacing.pagePaddingMobile;

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(hPad, AppSpacing.md, hPad, AppSpacing.xl),
            children: [
              _ProfileHeroCard(
                user: user,
                catalog: catalog,
                uploading: _uploading,
                onAvatarTap: () => _showPhotoOptions(user),
              ),
              const SizedBox(height: AppSpacing.md),
              _ProfileStreakCard(
                streakDays: user.streakDays,
                message: _streakMessage(user.streakDays),
                weekHighlights: _weekHighlights(user.streakDays),
              ),
              const SizedBox(height: AppSpacing.md),
              StreamBuilder<List<TaskModel>>(
                stream: _ninetyDayStream,
                builder: (context, ninetySnap) {
                  return StreamBuilder<List<TaskModel>>(
                    stream: _thirtyDayStream,
                    builder: (context, thirtySnap) {
                      final completedCount = ninetySnap.hasData
                          ? ninetySnap.data!
                              .where((t) =>
                                  t.assignedUserId == user.id &&
                                  t.statusId == catalog.completedStatusId)
                              .length
                          : null;
                      int? compliance;
                      if (thirtySnap.hasData) {
                        final userTasks = thirtySnap.data!
                            .where((t) => t.assignedUserId == user.id)
                            .toList();
                        if (userTasks.isNotEmpty) {
                          final completed = userTasks
                              .where(
                                  (t) => t.statusId == catalog.completedStatusId)
                              .length;
                          compliance =
                              (completed / userTasks.length * 100).round();
                        }
                      }
                      return _ProfileKpiGrid(
                        user: user,
                        completedCount: completedCount,
                        compliance: compliance,
                        isLoadingCompleted: !ninetySnap.hasData,
                        isLoadingCompliance: !thirtySnap.hasData,
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _ProfileAccountCard(user: user, catalog: catalog),
              const SizedBox(height: AppSpacing.md),
              const _SettingsCard(),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirm = await showConfirmDialog(
                    context,
                    title: 'Cerrar sesión',
                    message: '¿Estás seguro que deseas cerrar sesión?',
                    confirmLabel: 'Cerrar sesión',
                    destructive: true,
                    confirmForegroundColor: Colors.white,
                  );
                  if (confirm && context.mounted) {
                    try {
                      await context.read<AuthProvider>().signOut();
                    } catch (e) {
                      if (context.mounted) {
                        SnackbarUtils.showError(
                            context, SnackbarUtils.firebaseErrorMessage(e));
                      }
                    }
                  }
                },
                style: OutlinedButton.styleFrom(foregroundColor: colors.error),
                icon: const Icon(LucideIcons.logOut),
                label: const Text('Cerrar sesión'),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
          if (_uploading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x44000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Hero Card ─────────────────────────────────────────────────────────────────

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.user,
    required this.catalog,
    required this.uploading,
    required this.onAvatarTap,
  });

  final AppUser user;
  final CatalogProvider catalog;
  final bool uploading;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMobile = context.isMobile;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isMobile
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _HeroUserInfo(
                user: user,
                catalog: catalog,
                uploading: uploading,
                onAvatarTap: onAvatarTap,
                centered: true,
              ),
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: _HeroUserInfo(
                        user: user,
                        catalog: catalog,
                        uploading: uploading,
                        onAvatarTap: onAvatarTap,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _HeroDecorativePanel(),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HeroUserInfo extends StatelessWidget {
  const _HeroUserInfo({
    required this.user,
    required this.catalog,
    required this.uploading,
    required this.onAvatarTap,
    this.centered = false,
  });

  final AppUser user;
  final CatalogProvider catalog;
  final bool uploading;
  final VoidCallback onAvatarTap;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final align =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    final wrapAlign =
        centered ? WrapAlignment.center : WrapAlignment.start;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: uploading ? null : onAvatarTap,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              UserAvatarDisplay(user: user, size: 128, borderWidth: 3),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 2),
                ),
                child:
                    Icon(LucideIcons.camera, color: colors.onPrimary, size: 15),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          user.name,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          user.email,
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
          textAlign: textAlign,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: wrapAlign,
          children: [
            _ProfileChip(
              icon: LucideIcons.shieldCheck,
              label: AuthService.roleLabel(user.role),
            ),
            user.groupId != null
                ? _ProfileChip(
                    icon: LucideIcons.users,
                    label: catalog.groupName(user.groupId),
                  )
                : const _ProfileChip(
                    icon: LucideIcons.users,
                    label: 'Sin grupo',
                    muted: true,
                  ),
          ],
        ),
      ],
    );
  }
}

class _HeroDecorativePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base gradient
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary.withValues(alpha: 0.14),
                colors.primary.withValues(alpha: 0.04),
              ],
            ),
          ),
        ),
        // Large ring — top-right overflow
        Positioned(
          top: -50,
          right: -50,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.primary.withValues(alpha: 0.10),
                width: 1.5,
              ),
            ),
          ),
        ),
        // Filled circle — bottom-left overflow
        Positioned(
          bottom: -70,
          left: -40,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.06),
            ),
          ),
        ),
        // Small accent circle — mid-right
        Positioned(
          top: 48,
          right: 28,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.primary.withValues(alpha: 0.09),
            ),
          ),
        ),
        // CheCu brand logo — centered, very subtle
        Center(
          child: Opacity(
            opacity: 0.18,
            child: const BrandLogo(size: 80),
          ),
        ),
      ],
    );
  }
}

// ── Streak Card ───────────────────────────────────────────────────────────────

class _ProfileStreakCard extends StatelessWidget {
  const _ProfileStreakCard({
    required this.streakDays,
    required this.message,
    required this.weekHighlights,
  });

  final int streakDays;
  final String message;
  final List<bool> weekHighlights;

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMobile = context.isMobile;

    final content = isMobile
        ? _buildMobileLayout(colors)
        : _buildDesktopLayout(colors);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.primary.withValues(alpha: 0.30)),
      ),
      child: content,
    );
  }

  Widget _buildDesktopLayout(AppColorsExtension colors) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Block 1: flame + number
          _StreakCountBlock(streakDays: streakDays, colors: colors),
          _StreakDivider(colors: colors),
          // Block 2: label + message
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: _StreakMessageBlock(
                streakDays: streakDays,
                message: message,
                colors: colors,
              ),
            ),
          ),
          _StreakDivider(colors: colors),
          // Block 3: weekly mini-calendar
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: _WeekCalendar(
                dayLabels: _dayLabels,
                weekHighlights: weekHighlights,
                colors: colors,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(AppColorsExtension colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _StreakCountBlock(streakDays: streakDays, colors: colors),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _StreakMessageBlock(
                streakDays: streakDays,
                message: message,
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Divider(color: colors.primary.withValues(alpha: 0.15)),
        const SizedBox(height: AppSpacing.sm),
        _WeekCalendar(
          dayLabels: _dayLabels,
          weekHighlights: weekHighlights,
          colors: colors,
        ),
      ],
    );
  }
}

class _StreakCountBlock extends StatelessWidget {
  const _StreakCountBlock({required this.streakDays, required this.colors});

  final int streakDays;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.flame, color: colors.primary, size: 28),
          const SizedBox(height: 2),
          Text(
            '$streakDays',
            style: TextStyle(
              color: colors.primary,
              fontSize: 44,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakMessageBlock extends StatelessWidget {
  const _StreakMessageBlock({
    required this.streakDays,
    required this.message,
    required this.colors,
  });

  final int streakDays;
  final String message;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          streakDays == 1 ? 'día de racha' : 'días de racha',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            message,
            style: TextStyle(
              color: colors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekCalendar extends StatelessWidget {
  const _WeekCalendar({
    required this.dayLabels,
    required this.weekHighlights,
    required this.colors,
  });

  final List<String> dayLabels;
  final List<bool> weekHighlights;
  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (i) {
        final active = weekHighlights[i];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              dayLabels[i],
              style: TextStyle(
                color: active ? colors.primary : colors.textSecondary,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? colors.primary.withValues(alpha: 0.22)
                    : colors.primary.withValues(alpha: 0.05),
                border: Border.all(
                  color: active
                      ? colors.primary.withValues(alpha: 0.55)
                      : colors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: active
                  ? Icon(LucideIcons.check, color: colors.primary, size: 12)
                  : null,
            ),
          ],
        );
      }),
    );
  }
}

class _StreakDivider extends StatelessWidget {
  const _StreakDivider({required this.colors});

  final AppColorsExtension colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 52,
      color: colors.primary.withValues(alpha: 0.15),
    );
  }
}

// ── KPI Grid ──────────────────────────────────────────────────────────────────

class _ProfileKpiGrid extends StatelessWidget {
  const _ProfileKpiGrid({
    required this.user,
    required this.completedCount,
    required this.compliance,
    required this.isLoadingCompleted,
    required this.isLoadingCompliance,
  });

  final AppUser user;
  final int? completedCount;
  final int? compliance;
  final bool isLoadingCompleted;
  final bool isLoadingCompliance;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;
    final crossAxisCount = isDesktop ? 3 : isTablet ? 2 : 1;

    Color barColor = colors.textSecondary;
    if (compliance != null) {
      if (compliance! >= 80) {
        barColor = colors.success;
      } else if (compliance! >= 60) {
        barColor = colors.statusPending;
      } else {
        barColor = colors.error;
      }
    }

    final cards = <Widget>[
      _ProfileKpiCard(
        icon: LucideIcons.trophy,
        accentColor: const Color(0xFFD4AF37),
        label: 'Mejor racha',
        value: '${user.maxStreakDays}',
        suffix: user.maxStreakDays == 1 ? 'día' : 'días',
      ),
      _ProfileKpiCard(
        icon: LucideIcons.checkCircle,
        accentColor: const Color(0xFF43C97A),
        label: 'Completadas',
        value: isLoadingCompleted
            ? '…'
            : (completedCount != null ? '$completedCount' : '—'),
        suffix: '90 días',
      ),
      _ProfileComplianceKpiCard(
        compliance: compliance,
        isLoading: isLoadingCompliance,
        barColor: barColor,
      ),
    ];

    if (crossAxisCount == 1) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1)
              const SizedBox(height: AppSpacing.cardSpacing),
          ],
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: AppSpacing.cardSpacing,
        mainAxisSpacing: AppSpacing.cardSpacing,
        mainAxisExtent: 130,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => cards[i],
    );
  }
}

class _ProfileKpiCard extends StatefulWidget {
  const _ProfileKpiCard({
    required this.icon,
    required this.accentColor,
    required this.label,
    required this.value,
    required this.suffix,
  });

  final IconData icon;
  final Color accentColor;
  final String label;
  final String value;
  final String suffix;

  @override
  State<_ProfileKpiCard> createState() => _ProfileKpiCardState();
}

class _ProfileKpiCardState extends State<_ProfileKpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = widget.accentColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: _hovered ? accent.withValues(alpha: 0.45) : colors.divider,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? accent.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: _hovered ? 12 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(widget.icon, color: accent, size: 17),
            ),
            const Spacer(),
            Text(
              widget.value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              widget.suffix,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileComplianceKpiCard extends StatefulWidget {
  const _ProfileComplianceKpiCard({
    required this.compliance,
    required this.isLoading,
    required this.barColor,
  });

  final int? compliance;
  final bool isLoading;
  final Color barColor;

  @override
  State<_ProfileComplianceKpiCard> createState() =>
      _ProfileComplianceKpiCardState();
}

class _ProfileComplianceKpiCardState extends State<_ProfileComplianceKpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const accent = Color(0xFF4FA3F7);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color:
                _hovered ? accent.withValues(alpha: 0.45) : colors.divider,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? accent.withValues(alpha: 0.12)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: _hovered ? 12 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child:
                      const Icon(LucideIcons.pieChart, color: accent, size: 17),
                ),
                const Spacer(),
                Text(
                  '30 días',
                  style: TextStyle(color: colors.textSecondary, fontSize: 10),
                ),
              ],
            ),
            const Spacer(),
            if (widget.isLoading)
              LinearProgressIndicator(
                backgroundColor: colors.divider,
                color: accent,
              )
            else if (widget.compliance == null) ...[
              Text(
                'Sin datos',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ] else ...[
              Text(
                '${widget.compliance}%',
                style: TextStyle(
                  color: widget.barColor,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: widget.compliance! / 100.0,
                  minHeight: 5,
                  backgroundColor: colors.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(widget.barColor),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Cumplimiento',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Account Info Card ─────────────────────────────────────────────────────────

class _ProfileAccountCard extends StatelessWidget {
  const _ProfileAccountCard({required this.user, required this.catalog});

  final AppUser user;
  final CatalogProvider catalog;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDesktop = context.isDesktop;
    final isTablet = context.isTablet;

    final createdAtText = user.createdAt != null
        ? AppDateUtils.formatShortDate(user.createdAt!)
        : 'Sin información';

    final blocks = <Widget>[
      _AccountInfoBlock(
        icon: LucideIcons.shieldCheck,
        title: 'Rol',
        value: AuthService.roleLabel(user.role),
        subtitle: user.isSuperAdmin ? 'Administrador del sistema' : 'Colaborador',
      ),
      _AccountInfoBlock(
        icon: LucideIcons.users,
        title: 'Grupo',
        value: user.groupId != null ? catalog.groupName(user.groupId) : 'Sin grupo',
        subtitle: user.groupId != null ? 'Grupo asignado' : 'Sin asignación',
      ),
      _AccountInfoBlock(
        icon: LucideIcons.mail,
        title: 'Correo',
        value: user.email,
        subtitle: 'Cuenta de acceso',
      ),
      _AccountInfoBlock(
        icon: LucideIcons.calendar,
        title: 'Miembro desde',
        value: createdAtText,
        subtitle: 'Fecha de registro',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(LucideIcons.user, color: colors.primary, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Información de la cuenta',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (isDesktop)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < blocks.length; i++) ...[
                    Expanded(child: blocks[i]),
                    if (i < blocks.length - 1)
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md),
                        color: colors.divider,
                      ),
                  ],
                ],
              ),
            )
          else if (isTablet)
            Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: blocks[0]),
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md),
                        color: colors.divider,
                      ),
                      Expanded(child: blocks[1]),
                    ],
                  ),
                ),
                Divider(color: colors.divider, height: AppSpacing.lg),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: blocks[2]),
                      Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md),
                        color: colors.divider,
                      ),
                      Expanded(child: blocks[3]),
                    ],
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  blocks[i],
                  if (i < blocks.length - 1) Divider(color: colors.divider),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _AccountInfoBlock extends StatelessWidget {
  const _AccountInfoBlock({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: colors.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              title,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          subtitle,
          style: TextStyle(color: colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}

// ── Profile chip badge ────────────────────────────────────────────────────────

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = muted ? colors.textSecondary : colors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: muted ? colors.textSecondary : colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings card ─────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      ),
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusSm + 2),
              ),
              child: Icon(LucideIcons.settings, color: colors.primary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuración',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    'Personaliza apariencia y preferencias',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight,
                color: colors.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}
