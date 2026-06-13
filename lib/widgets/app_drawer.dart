import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';
import '../providers/catalog_provider.dart';
import '../screens/admin/admin_panel_page.dart';
import '../services/auth_service.dart';
import 'confirm_dialog.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final catalog = context.watch<CatalogProvider>();
    final user = auth.appUser;

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.divider),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.gold, width: 1.5),
                        ),
                        child: const Icon(LucideIcons.userCircle,
                            color: AppColors.gold, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.name ?? '',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user?.email ?? '',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
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
            if (auth.isSuperAdmin)
              ListTile(
                leading: const Icon(LucideIcons.layoutDashboard, color: AppColors.gold),
                title: const Text('Panel de administración'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminPanelPage()),
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
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(LucideIcons.logOut, color: AppColors.error),
              title: const Text('Cerrar sesión', style: TextStyle(color: AppColors.error)),
              onTap: () async {
                final confirm = await showConfirmDialog(
                  context,
                  title: 'Cerrar sesión',
                  message: '¿Estás seguro que deseas cerrar sesión?',
                  confirmLabel: 'Cerrar sesión',
                  destructive: true,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
