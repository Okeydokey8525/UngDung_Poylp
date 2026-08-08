import 'package:app_polyp/app/app_theme.dart';
import 'package:app_polyp/app/theme_controller.dart';
import 'package:app_polyp/core/config/app_config.dart';
import 'package:app_polyp/core/config/invalid_configuration_screen.dart';
import 'package:app_polyp/navigation/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Legacy Spring-backed mobile flow retained temporarily for rollback until M7.
class LegacyPolypVisionApp extends ConsumerWidget {
  const LegacyPolypVisionApp({super.key, this.configurationError});

  final String? configurationError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreference = ref.watch(themeControllerProvider);
    final configError = configurationError ?? AppConfig.validationError;

    if (configError != null) {
      return MaterialApp(
        title: 'PolypVision',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themePreference.mode,
        home: const InvalidConfigurationScreen(),
      );
    }

    return MaterialApp.router(
      title: 'PolypVision',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themePreference.mode,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
