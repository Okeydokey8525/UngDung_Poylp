import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themePreferenceKey = 'polypvision-theme';

enum AppThemePreference {
  system,
  light,
  dark;

  ThemeMode get mode => switch (this) {
    AppThemePreference.system => ThemeMode.system,
    AppThemePreference.light => ThemeMode.light,
    AppThemePreference.dark => ThemeMode.dark,
  };

  String get label => switch (this) {
    AppThemePreference.system => 'Theo hệ thống',
    AppThemePreference.light => 'Sáng',
    AppThemePreference.dark => 'Tối',
  };
}

typedef SharedPreferencesLoader = Future<SharedPreferences> Function();

final sharedPreferencesLoaderProvider = Provider<SharedPreferencesLoader>(
  (ref) => SharedPreferences.getInstance,
);

final themeControllerProvider =
    NotifierProvider<ThemeController, AppThemePreference>(ThemeController.new);

class ThemeController extends Notifier<AppThemePreference> {
  @override
  AppThemePreference build() {
    Future<void>.microtask(_restore);
    return AppThemePreference.system;
  }

  Future<void> setPreference(AppThemePreference preference) async {
    state = preference;
    try {
      final preferences = await ref.read(sharedPreferencesLoaderProvider)();
      await preferences.setString(_themePreferenceKey, preference.name);
    } catch (_) {
      // Theme still changes for the current session.
    }
  }

  Future<void> _restore() async {
    try {
      final preferences = await ref.read(sharedPreferencesLoaderProvider)();
      final saved = preferences.getString(_themePreferenceKey);
      state = AppThemePreference.values.firstWhere(
        (preference) => preference.name == saved,
        orElse: () => AppThemePreference.system,
      );
    } catch (_) {
      state = AppThemePreference.system;
    }
  }
}
