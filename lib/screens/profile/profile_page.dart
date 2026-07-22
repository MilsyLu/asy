import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
import '../../widgets/confirm_dialog.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/user_avatar.dart';

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

  /// Builds the "Elegir de galería / Tomar foto / Eliminar foto / Cancelar"
  /// option list shared by both presentations below — the content never
  /// differs, only the container around it does.
  List<Widget> _photoOptionTiles(
    BuildContext dialogOrSheetContext,
    AppUser user,
  ) {
    final colors = context.colors;
    void pop() => Navigator.of(dialogOrSheetContext).pop();
    return [
      if (!kIsWeb)
        ListTile(
          leading: Icon(LucideIcons.camera, color: colors.primary),
          title: const Text('Tomar foto'),
          onTap: () {
            pop();
            _pickPhoto(ImageSource.camera, user.id);
          },
        ),
      ListTile(
        leading: Icon(LucideIcons.image, color: colors.primary),
        title: const Text('Elegir de galería'),
        onTap: () {
          pop();
          _pickPhoto(ImageSource.gallery, user.id);
        },
      ),
      if (user.photoUrl != null && user.photoUrl!.isNotEmpty)
        ListTile(
          leading: Icon(LucideIcons.trash2, color: colors.error),
          title: Text('Eliminar foto', style: TextStyle(color: colors.error)),
          onTap: () {
            pop();
            _deletePhoto(user.id);
          },
        ),
      ListTile(
        leading: Icon(LucideIcons.x, color: colors.textSecondary),
        title: const Text('Cancelar'),
        onTap: pop,
      ),
    ];
  }

  /// Mobile: bottom sheet (the standard mobile pattern for this kind of
  /// action list). Tablet/desktop: a centered floating dialog instead — a
  /// sheet pinned to the bottom of a tall desktop viewport could render
  /// clipped/oddly placed, and "floating like the task detail dialog" is
  /// exactly the reference the user asked for.
  Future<void> _showPhotoOptions(AppUser user) async {
    final colors = context.colors;
    if (context.isMobile) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetCtx) => SafeArea(
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
              ..._photoOptionTiles(sheetCtx, user),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Foto de perfil',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ..._photoOptionTiles(dialogCtx, user),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-size, zoomable view of the current profile photo — the "ver la
  /// imagen" affordance that was missing (tapping the avatar only offered
  /// ways to change it). Reached by tapping the avatar photo itself; the
  /// small camera badge on top of it still opens [_showPhotoOptions].
  void _showPhotoViewer(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Container(
                    width: 240,
                    height: 240,
                    color: Colors.black26,
                    child: const Icon(LucideIcons.imageOff,
                        color: Colors.white70, size: 40),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                icon: const Icon(LucideIcons.x, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  shape: const CircleBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tap target for the avatar photo itself (not the camera badge): view it
  /// full-size if there's a real photo, otherwise fall through to the
  /// upload options (nothing to view yet).
  void _onAvatarPhotoTap(AppUser user) {
    final url = user.photoUrl;
    if (url != null && url.isNotEmpty) {
      _showPhotoViewer(url);
    } else {
      _showPhotoOptions(user);
    }
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
                onAvatarTap: () => _onAvatarPhotoTap(user),
                onEditPhotoTap: () => _showPhotoOptions(user),
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
              // Tablet/desktop: Rol/Equipo/Correo/Miembro desde now live in the
              // Hero (see _HeroUserInfo), and Configuración/Cerrar sesión are
              // already permanent Sidebar entries (main_shell.dart) — showing
              // them again here would just be the same data/actions in two
              // places. Mobile has neither a Hero-integrated info grid nor a
              // permanent sidebar (it gets AppDrawer instead), so it keeps
              // these three exactly as before.
              if (context.isMobile) ...[
                const SizedBox(height: AppSpacing.md),
                _ProfileAccountCard(user: user, catalog: catalog),
                const SizedBox(height: AppSpacing.md),
                // Configuración lives in AppDrawer (mobile's nav menu) —
                // showing it again here was the same entry in two places.
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
              ],
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
    required this.onEditPhotoTap,
  });

  final AppUser user;
  final CatalogProvider catalog;
  final bool uploading;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditPhotoTap;

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
                onEditPhotoTap: onEditPhotoTap,
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
                        onEditPhotoTap: onEditPhotoTap,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Align(
                        alignment: Alignment.center,
                        child: _HeroInfoGrid(user: user, catalog: catalog),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Human-readable tenure ("3 meses", "2 años", "5 días") from [createdAt] to
/// now — richer context than a bare date for "Miembro desde".
String _tenureLabel(DateTime? createdAt) {
  if (createdAt == null) return '';
  final days = DateTime.now().difference(createdAt).inDays;
  if (days < 1) return 'Hoy';
  if (days < 30) return '$days ${days == 1 ? 'día' : 'días'}';
  if (days < 365) {
    final months = (days / 30).floor();
    return '$months ${months == 1 ? 'mes' : 'meses'}';
  }
  final years = (days / 365).floor();
  return '$years ${years == 1 ? 'año' : 'años'}';
}

class _HeroUserInfo extends StatelessWidget {
  const _HeroUserInfo({
    required this.user,
    required this.catalog,
    required this.uploading,
    required this.onAvatarTap,
    required this.onEditPhotoTap,
    this.centered = false,
  });

  final AppUser user;
  final CatalogProvider catalog;
  final bool uploading;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditPhotoTap;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isMobile = context.isMobile;
    final align =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = centered ? TextAlign.center : TextAlign.start;

    // Tablet/desktop gets a bigger, more prominent avatar (per user request)
    // with a soft accent glow behind it; mobile keeps the original size.
    final avatarSize = isMobile ? 128.0 : 180.0;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            Container(
              decoration: isMobile
                  ? null
                  : BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.28),
                          blurRadius: 28,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
              child: GestureDetector(
                // Tapping the photo itself views it (or starts upload if
                // there's nothing to view yet) — separate from the camera
                // badge below, which always opens the change/remove menu.
                onTap: uploading ? null : onAvatarTap,
                child: UserAvatarDisplay(
                    user: user, size: avatarSize, borderWidth: 3),
              ),
            ),
            GestureDetector(
              onTap: uploading ? null : onEditPhotoTap,
              child: Container(
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
            ),
          ],
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
        if (isMobile) ...[
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
            alignment: WrapAlignment.center,
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
                      label: 'Sin equipo',
                      muted: true,
                    ),
            ],
          ),
        ],
        // Tablet/desktop: Rol/Equipo/Correo/Miembro desde now sit in their
        // own grid *beside* the avatar (see _ProfileHeroCard), not stacked
        // underneath it — the old decorative side panel was replaced by
        // that grid instead of duplicating this data in a separate card.
      ],
    );
  }
}

/// The Rol/Equipo/Correo/Miembro-desde grid embedded in the Hero on
/// tablet/desktop — reuses [_AccountInfoBlock] (previously only used by the
/// now tablet/desktop-hidden `_ProfileAccountCard`) so both places stay in
/// sync if the fields ever change.
class _HeroInfoGrid extends StatelessWidget {
  const _HeroInfoGrid({required this.user, required this.catalog});

  final AppUser user;
  final CatalogProvider catalog;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final createdAtText = user.createdAt != null
        ? AppDateUtils.formatShortDate(user.createdAt!)
        : 'Sin información';
    final tenure = _tenureLabel(user.createdAt);

    // Role gets its own accent (gold for super_admin, primary for regular
    // workers) instead of the uniform icon color the other three blocks
    // use — a quick visual cue for "who am I looking at" without reading
    // the text.
    final roleColor =
        user.isSuperAdmin ? const Color(0xFFD4AF37) : colors.primary;

    final rows = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _AccountInfoBlock(
              icon: LucideIcons.shieldCheck,
              iconColor: roleColor,
              title: 'Rol',
              value: AuthService.roleLabel(user.role),
              subtitle:
                  user.isSuperAdmin ? 'Administrador del sistema' : 'Colaborador',
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: _AccountInfoBlock(
              icon: LucideIcons.users,
              title: 'Equipo',
              value:
                  user.groupId != null ? catalog.groupName(user.groupId) : 'Sin equipo',
              subtitle: user.groupId != null ? 'Equipo asignado' : 'Sin asignación',
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _AccountInfoBlock(
              icon: LucideIcons.mail,
              title: 'Correo',
              value: user.email,
              subtitle: 'Cuenta de acceso',
              trailing: _CopyIconButton(text: user.email),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: _AccountInfoBlock(
              icon: LucideIcons.calendar,
              title: 'Miembro desde',
              value: createdAtText,
              subtitle: tenure.isEmpty ? 'Fecha de registro' : 'Hace $tenure',
            ),
          ),
        ],
      ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }
}

/// Small copy-to-clipboard icon button — used next to the Correo value so
/// copying the email doesn't require selecting text manually.
class _CopyIconButton extends StatefulWidget {
  const _CopyIconButton({required this.text});

  final String text;

  @override
  State<_CopyIconButton> createState() => _CopyIconButtonState();
}

class _CopyIconButtonState extends State<_CopyIconButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: _copied ? 'Copiado' : 'Copiar correo',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _copy,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            _copied ? LucideIcons.check : LucideIcons.copy,
            size: 14,
            color: _copied ? colors.success : colors.textSecondary,
          ),
        ),
      ),
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
        icon: LucideIcons.checkCircle,
        accentColor: const Color(0xFF43C97A),
        label: 'Completadas',
        value: isLoadingCompleted
            ? '…'
            : (completedCount != null ? '$completedCount' : '—'),
        suffix: '90 días',
      ),
      _ProfileKpiCard(
        icon: LucideIcons.trophy,
        accentColor: const Color(0xFFD4AF37),
        label: 'Mejor racha',
        value: '${user.maxStreakDays}',
        suffix: user.maxStreakDays == 1 ? 'día' : 'días',
      ),
      _ProfileComplianceKpiCard(
        compliance: compliance,
        isLoading: isLoadingCompliance,
        barColor: barColor,
      ),
    ];

    // Always 3 across, on every screen size — narrow phones just get
    // narrower cards (compact padding + wrapping labels below) instead of
    // stacking to one-per-row and pushing the rest below the fold.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.cardSpacing,
        // Tall enough for a 2-line wrapped label on the narrowest phones.
        mainAxisExtent: 140,
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: accent.withValues(alpha: _hovered ? 0.6 : 0.35),
            width: _hovered ? 1.5 : 1.25,
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
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(widget.icon, color: accent, size: 16),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.value,
              style: TextStyle(
                color: accent,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
            Text(
              widget.suffix,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary, fontSize: 10),
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: widget.barColor.withValues(alpha: _hovered ? 0.6 : 0.35),
            width: _hovered ? 1.5 : 1.25,
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
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(LucideIcons.pieChart, color: accent, size: 16),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Cumplimiento',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (widget.isLoading)
              SizedBox(
                width: 80,
                child: LinearProgressIndicator(
                  backgroundColor: colors.divider,
                  color: accent,
                ),
              )
            else if (widget.compliance == null) ...[
              Text(
                'Sin datos',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ] else ...[
              Text(
                '${widget.compliance}%',
                style: TextStyle(
                  color: widget.barColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: widget.compliance! / 100.0,
                    minHeight: 5,
                    backgroundColor: colors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(widget.barColor),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '30 días',
              style: TextStyle(color: colors.textSecondary, fontSize: 10),
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
        title: 'Equipo',
        value: user.groupId != null ? catalog.groupName(user.groupId) : 'Sin equipo',
        subtitle: user.groupId != null ? 'Equipo asignado' : 'Sin asignación',
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
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  /// Overrides the icon's default `colors.primary` — used for the Rol block
  /// in the Hero grid so role has its own accent at a glance.
  final Color? iconColor;

  /// Optional trailing widget next to the title row (e.g. a copy button for
  /// Correo).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: iconColor ?? colors.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            ?trailing,
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

