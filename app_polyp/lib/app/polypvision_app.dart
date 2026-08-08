import 'package:app_polyp/app/app_theme.dart';
import 'package:app_polyp/app/theme_controller.dart';
import 'package:app_polyp/core/config/ai_service_config.dart';
import 'package:app_polyp/core/config/invalid_configuration_screen.dart';
import 'package:app_polyp/navigation/direct_ai_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PolypVisionApp extends ConsumerWidget {
  const PolypVisionApp({super.key, this.configurationError});

  final String? configurationError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreference = ref.watch(themeControllerProvider);
    String? configError = configurationError;
    if (configError == null) {
      try {
        AiServiceConfig.fromEnvironment();
      } on FormatException catch (error) {
        configError = error.message;
      }
    }

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
      routerConfig: ref.watch(directAiRouterProvider),
    );
  }
}
