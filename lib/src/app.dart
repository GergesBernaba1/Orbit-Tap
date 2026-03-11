import 'package:flutter/material.dart';

import 'screens/decoy_game_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/android_source_access_service.dart';
import 'services/contact_service.dart';
import 'services/media_export_service.dart';
import 'services/private_apps_service.dart';
import 'services/security_service.dart';
import 'services/shared_media_removal_service.dart';
import 'services/vault_repository.dart';
import 'state/vault_controller.dart';

class OrbitTapApp extends StatefulWidget {
  const OrbitTapApp({super.key});

  @override
  State<OrbitTapApp> createState() => _OrbitTapAppState();
}

class _OrbitTapAppState extends State<OrbitTapApp> {
  late final VaultController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VaultController(
      securityService: SecurityService(),
      vaultRepository: VaultRepository(),
      contactService: ContactService(),
      privateAppsService: PrivateAppsService(),
      mediaExportService: MediaExportService(),
      sharedMediaRemovalService: SharedMediaRemovalService(),
      androidSourceAccessService: AndroidSourceAccessService(),
    )..initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF003049),
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F3E9),
      useMaterial3: true,
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Orbit Tap',
          theme: theme,
          home: switch (_controller.stage) {
            AppStage.loading => const _SplashScreen(),
            AppStage.onboarding => OnboardingScreen(controller: _controller),
            AppStage.decoy => DecoyGameScreen(controller: _controller),
            AppStage.ready => HomeScreen(controller: _controller),
          },
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

