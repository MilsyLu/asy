import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/theme_manager.dart';
import 'providers/auth_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/system_config_provider.dart';
import 'screens/auth/login_page.dart';
import 'screens/main_shell.dart';
import 'screens/platform/platform_admin_shell.dart';
import 'services/app_update_service.dart';
import 'services/auth_service.dart';
import 'services/catalog_repository.dart';
import 'services/notification_navigation.dart';
import 'services/notification_repository.dart';
import 'services/printer_config_repository.dart';
import 'services/task_repository.dart';
import 'services/user_repository.dart';
import 'widgets/brand_logo.dart';

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Multi-tenant: TaskRepository/CatalogRepository/UserRepository/
        // NotificationRepository all need the signed-in user's empresaId to
        // scope their queries, which isn't known until AuthProvider resolves
        // it — so they're constructed further down, in `builder` below
        // (same trick already used for CatalogProvider), not here at the
        // MultiProvider root. AuthService stays root-level since it's used
        // pre-login (sign-in, password reset).
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, ThemeManager>(
          create: (_) => ThemeManager(),
          update: (_, auth, manager) {
            final themeManager = manager ?? ThemeManager();
            themeManager.updateFromUser(auth.appUser);
            return themeManager;
          },
        ),
      ],
      child: Builder(
        builder: (context) {
          final themeManager = context.watch<ThemeManager>();
          return MaterialApp(
            navigatorKey: rootNavigatorKey,
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: themeManager.lightTheme,
            darkTheme: themeManager.darkTheme,
            themeMode: themeManager.themeMode,
            locale: const Locale('es'),
            supportedLocales: const [Locale('es'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AuthGate(),
            // `builder` wraps the Navigator itself, so this provider covers
            // `home` AND every page/dialog pushed with Navigator.push or
            // showDialog. Placing it on `home` (as a child of AuthGate)
            // would only cover the first route: pushed routes are siblings
            // of `home` inside the Overlay, not its descendants, so they
            // couldn't see it.
            builder: (context, child) {
              final user = context.watch<AuthProvider>().appUser;
              // Platform owners never reach here with a non-null appUser
              // (AuthProvider deliberately leaves it null for them — see
              // isPlatformOwner) so none of these tenant-scoped
              // repositories/providers are ever constructed for a platform
              // owner session.
              if (user == null) return child!;
              final empresaId = user.empresaId!;
              return MultiProvider(
                providers: [
                  Provider<TaskRepository>(create: (_) => TaskRepository(empresaId: empresaId)),
                  Provider<CatalogRepository>(create: (_) => CatalogRepository(empresaId: empresaId)),
                  Provider<UserRepository>(create: (_) => UserRepository(empresaId: empresaId)),
                  Provider<NotificationRepository>(create: (_) => NotificationRepository()),
                  Provider<PrinterConfigRepository>(create: (_) => PrinterConfigRepository(empresaId: empresaId)),
                ],
                child: ChangeNotifierProvider<AppUpdateService>(
                  create: (_) => AppUpdateService(),
                  child: ChangeNotifierProvider<SystemConfigProvider>(
                    create: (_) => SystemConfigProvider(),
                    child: ChangeNotifierProvider<CatalogProvider>(
                      key: ValueKey(user.id),
                      create: (_) => CatalogProvider(empresaId: empresaId),
                      child: child!,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Decides whether to show the login flow or the authenticated app
/// shell based on [AuthProvider]'s state.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.isLoading) {
      return const _BootSplash();
    }

    if (!auth.isAuthenticated) {
      return const LoginPage();
    }

    // Checked before the tenant appUser check below — a platform owner
    // (Michel) has no `users/{uid}` profile at all, by design (see
    // AuthProvider._onAuthChanged).
    if (auth.isPlatformOwner) {
      return const PlatformAdminShell();
    }

    if (auth.appUser == null) {
      return const LoginPage();
    }

    return const MainShell();
  }
}

/// Branded boot screen shown only while [AuthProvider] resolves the signed-in
/// user (Sprint 7.3.2B/C), right after the native splash hands off to the
/// first Flutter frame. Uses the same fixed institutional colors/logo as
/// Login — deliberately not [LoadingIndicator] (used by many in-app loading
/// states that must keep following the user's selected theme) and
/// deliberately not theme-dependent, since no user/role is known yet here.
class _BootSplash extends StatefulWidget {
  const _BootSplash();

  @override
  State<_BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<_BootSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.brandBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        // Coin-flip wobble: eases between 0 and half a turn
                        // and back (never a continuous 360° spin), with a
                        // matching subtle 1.00 -> 1.04 -> 1.00 scale pulse.
                        final t = Curves.easeInOut.transform(_controller.value);
                        final angle = t * math.pi;
                        final scale = 1.0 + (t * 0.04);
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle)
                            ..scaleByDouble(scale, scale, scale, 1.0),
                          child: child,
                        );
                      },
                      child: const BrandLogo(size: 96),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      AppConstants.appName,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.brandPrimary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppConstants.appTagline,
                      style: TextStyle(color: AppConstants.brandPrimary.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                AppConstants.appDeveloper,
                style: TextStyle(
                  color: AppConstants.brandPrimary.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
