import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/catalog_provider.dart';
import 'screens/auth/login_page.dart';
import 'screens/main_shell.dart';
import 'services/auth_service.dart';
import 'services/catalog_repository.dart';
import 'services/task_repository.dart';
import 'services/user_repository.dart';
import 'widgets/loading_indicator.dart';

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<UserRepository>(create: (_) => UserRepository()),
        Provider<TaskRepository>(create: (_) => TaskRepository()),
        Provider<CatalogRepository>(create: (_) => CatalogRepository()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ],
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
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
          if (user == null) return child!;
          return ChangeNotifierProvider<CatalogProvider>(
            key: ValueKey(user.id),
            create: (_) => CatalogProvider(),
            child: child!,
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
      return const Scaffold(body: LoadingIndicator(message: 'Cargando...'));
    }

    if (!auth.isAuthenticated || auth.appUser == null) {
      return const LoginPage();
    }

    return const MainShell();
  }
}
