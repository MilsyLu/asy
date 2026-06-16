import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/theme_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../screens/admin/admin_panel_page.dart';
import '../screens/profile/settings_page.dart';
import '../screens/trash/trash_page.dart';
import '../services/auth_service.dart';
import 'confirm_dialog.dart';
import 'user_avatar.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final catalog = context.watch<CatalogProvider>();
    final user = auth.appUser;
    final colors = context.colors;

    return Drawer(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.divider),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      user != null
                        ? UserAvatarDisplay(
                            user: user, size: 48, borderWidth: 1.5)
                        : Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: colors.primary, width: 1.5),
                            ),
                            child: Icon(LucideIcons.userCircle,
                                color: colors.primary, size: 28),
                          ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? '',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user?.email ?? '',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Badge(
                        icon: LucideIcons.userCheck,
                        label: AuthService.roleLabel(user?.role ?? ''),
                      ),
                      if (user?.groupId != null)
                        _Badge(
                          icon: LucideIcons.users,
                          label: catalog.groupName(user?.groupId),
                        ),
                      _Badge(
                        icon: LucideIcons.barChart3,
                        label: '${user?.streakDays ?? 0} días racha',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (auth.isSuperAdmin) ...[
              ListTile(
                leading: Icon(LucideIcons.layoutDashboard, color: colors.primary),
                title: const Text('Panel de administración'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminPanelPage()),
                  );
                },
              ),
              ListTile(
                leading: Icon(LucideIcons.trash2, color: colors.primary),
                title: const Text('Papelera'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TrashPage()),
                  );
                },
              ),
            ],
            ListTile(
              leading: Icon(LucideIcons.settings, color: colors.primary),
              title: const Text('Configuración'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            const Spacer(),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                AppConstants.appName,
                style: TextStyle(
                  color: colors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ),
            ListTile(
              leading: Icon(LucideIcons.logOut, color: colors.error),
              title: Text('Cerrar sesión', style: TextStyle(color: colors.error)),
              onTap: () async {
                final confirm = await showConfirmDialog(
                  context,
                  title: 'Cerrar sesión',
                  message: '¿Estás seguro que deseas cerrar sesión?',
                  confirmLabel: 'Cerrar sesión',
                  destructive: true,
                  confirmForegroundColor: Colors.white,
                );
                if (confirm && context.mounted) {
                  await context.read<AuthProvider>().signOut();
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
