import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

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
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _uploading = false;
  Future<List<TaskModel>>? _thirtyDaysFuture;
  Future<List<TaskModel>>? _ninetyDaysFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_thirtyDaysFuture == null) {
      final repo = context.read<TaskRepository>();
      final now = DateTime.now();
      _thirtyDaysFuture =
          repo.getTasksInRange(now.subtract(const Duration(days: 30)), now);
      _ninetyDaysFuture =
          repo.getTasksInRange(now.subtract(const Duration(days: 90)), now);
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
                leading:
                    Icon(LucideIcons.x, color: colors.textSecondary),
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
      final url =
          await StorageService.uploadProfilePhoto(uid, File(picked.path));
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

    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeroCard(
                user: user,
                catalog: catalog,
                uploading: _uploading,
                onAvatarTap: () => _showPhotoOptions(user),
              ),
              const SizedBox(height: 16),
              _StreakCard(
                streakDays: user.streakDays,
                message: _streakMessage(user.streakDays),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<TaskModel>>(
                future: _ninetyDaysFuture,
                builder: (context, snapshot) {
                  final completedCount = snapshot.hasData
                      ? snapshot.data!
                          .where((t) =>
                              t.assignedUserId == user.id &&
                              t.statusId == catalog.completedStatusId)
                          .length
                      : null;
                  return Row(
                    children: [
                      Expanded(
                        child: _MiniStatCard(
                          icon: LucideIcons.trophy,
                          value: '${user.maxStreakDays}',
                          label: 'Mejor racha',
                          suffix:
                              user.maxStreakDays == 1 ? 'día' : 'días',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MiniStatCard(
                          icon: LucideIcons.checkCircle,
                          value: completedCount != null
                              ? '$completedCount'
                              : '—',
                          label: 'Completadas',
                          suffix: '90 días',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<TaskModel>>(
                future: _thirtyDaysFuture,
                builder: (context, snapshot) {
                  int? compliance;
                  if (snapshot.hasData) {
                    final userTasks = snapshot.data!
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
                  return _ComplianceCard(
                    compliance: compliance,
                    lastLogin: user.lastLogin,
                    isLoading:
                        snapshot.connectionState != ConnectionState.done,
                  );
                },
              ),
              const SizedBox(height: 12),
              const _SettingsCard(),
              const SizedBox(height: 16),
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
              const SizedBox(height: 24),
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

// ---------------------------------------------------------------------------
// Hero card: avatar + name + email + role/group badges
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: uploading ? null : onAvatarTap,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                UserAvatarDisplay(user: user, size: 112, borderWidth: 3),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                  child: Icon(
                    LucideIcons.camera,
                    color: colors.onPrimary,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            user.name,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            user.email,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _ProfileBadge(
                icon: LucideIcons.shieldCheck,
                label: AuthService.roleLabel(user.role),
              ),
              user.groupId != null
                  ? _ProfileBadge(
                      icon: LucideIcons.users,
                      label: catalog.groupName(user.groupId),
                    )
                  : const _ProfileBadge(
                      icon: LucideIcons.users,
                      label: 'Sin grupo',
                      muted: true,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({
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
        color: color.withValues(alpha: 0.1),
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

// ---------------------------------------------------------------------------
// Streak protagonist card — intentionally the largest element on the screen
// ---------------------------------------------------------------------------

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.streakDays, required this.message});

  final int streakDays;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.flame, color: colors.primary, size: 30),
              const SizedBox(height: 2),
              Text(
                '$streakDays',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  streakDays == 1 ? 'día de racha' : 'días de racha',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini stat card: best streak / completed tasks
// ---------------------------------------------------------------------------

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.suffix,
  });

  final IconData icon;
  final String value;
  final String label;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.primary, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: colors.primary,
              fontSize: 30,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            suffix,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compliance card: % completed tasks + progress bar + last login
// ---------------------------------------------------------------------------

class _ComplianceCard extends StatelessWidget {
  const _ComplianceCard({
    required this.compliance,
    required this.lastLogin,
    required this.isLoading,
  });

  final int? compliance;
  final DateTime? lastLogin;
  final bool isLoading;

  Color _barColor(AppColorsExtension colors) {
    if (compliance == null) return colors.textSecondary;
    if (compliance! >= 80) return colors.success;
    if (compliance! >= 60) return colors.statusPending;
    return colors.error;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final barColor = _barColor(colors);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.pieChart, color: colors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                'Cumplimiento',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Text(
                '30 días',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading)
            LinearProgressIndicator(
              backgroundColor: colors.divider,
              color: colors.primary,
            )
          else if (compliance == null) ...[
            Text(
              'Sin datos',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'No hay tareas asignadas en los últimos 30 días.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$compliance%',
                  style: TextStyle(
                    color: barColor,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'completadas',
                  style:
                      TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: compliance! / 100.0,
                minHeight: 8,
                backgroundColor: colors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
          ],
          if (lastLogin != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(LucideIcons.clock,
                    color: colors.textSecondary, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Último ingreso: ',
                  style:
                      TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
                Flexible(
                  child: Text(
                    AppDateUtils.formatDateTimeOrDash(lastLogin),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings navigation card
// ---------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(LucideIcons.settings,
                  color: colors.primary, size: 20),
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
                    style: TextStyle(
                        color: colors.textSecondary, fontSize: 12),
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
