import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_colors.dart';
import '../../providers/auth_provider.dart';
import 'empresas_page.dart';

/// Root screen for a platform-owner session (Michel) — shown by `AuthGate`
/// in `app.dart` instead of `MainShell` whenever `AuthProvider.isPlatformOwner`
/// is true. Deliberately minimal and entirely separate from the tenant app
/// shell: no `CatalogProvider`, no tenant-scoped repositories are ever
/// constructed for this session (see `app.dart`'s `builder`, gated on
/// `appUser != null`, which platform owners never have).
class PlatformAdminShell extends StatelessWidget {
  const PlatformAdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.surface,
        title: const Text('Panel de plataforma'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () => context.read<AuthProvider>().signOut(),
          ),
        ],
      ),
      body: const EmpresasPage(),
    );
  }
}
