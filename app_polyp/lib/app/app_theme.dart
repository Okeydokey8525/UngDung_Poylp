import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/app/app_typography.dart';
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    primary: AppColors.lightPrimary,
    onPrimary: Colors.white,
    secondary: AppColors.lightAccent,
    body: AppColors.lightBody,
    heading: AppColors.lightHeading,
    border: AppColors.lightBorder,
    semantic: AppSemanticColors.light(),
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    primary: AppColors.darkPrimary,
    onPrimary: AppColors.darkBackground,
    secondary: AppColors.darkAccent,
    body: AppColors.darkBody,
    heading: AppColors.darkHeading,
    border: AppColors.darkBorder,
    semantic: AppSemanticColors.dark(),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color primary,
    required Color onPrimary,
    required Color secondary,
    required Color body,
    required Color heading,
    required Color border,
    required AppSemanticColors semantic,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: brightness == Brightness.light
          ? Colors.white
          : AppColors.darkBackground,
      error: semantic.danger,
      onError: brightness == Brightness.light
          ? Colors.white
          : AppColors.darkBackground,
      surface: surface,
      onSurface: body,
      outline: border,
      surfaceContainer: semantic.surfaceAlt,
    );
    final radiusSmall = BorderRadius.circular(AppColors.radiusSmall);
    final radiusLarge = BorderRadius.circular(AppColors.radiusLarge);
    final borderSide = BorderSide(color: border);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: AppTypography.textTheme(body, heading),
      extensions: [semantic],
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: heading,
        titleTextStyle: AppTypography.textTheme(body, heading).titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusLarge,
          side: borderSide,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: semantic.input,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: borderSide,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: borderSide,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusSmall,
          borderSide: BorderSide(color: semantic.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, AppColors.interactiveMinHeight),
          shape: RoundedRectangleBorder(borderRadius: radiusSmall),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(44, AppColors.interactiveMinHeight),
          side: borderSide,
          shape: RoundedRectangleBorder(borderRadius: radiusSmall),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, AppColors.interactiveMinHeight),
          shape: RoundedRectangleBorder(borderRadius: radiusSmall),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: surface,
        indicatorColor: semantic.primarySoft,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: body, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: semantic.primarySoft,
        selectedIconTheme: IconThemeData(color: primary),
        selectedLabelTextStyle: TextStyle(
          color: primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedIconTheme: IconThemeData(color: semantic.muted),
        unselectedLabelTextStyle: TextStyle(color: semantic.muted),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: radiusLarge),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppColors.radiusLarge),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: heading,
        contentTextStyle: TextStyle(color: background),
        shape: RoundedRectangleBorder(borderRadius: radiusSmall),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: semantic.surfaceAlt,
        selectedColor: semantic.primarySoft,
        side: borderSide,
        shape: RoundedRectangleBorder(borderRadius: radiusSmall),
        labelStyle: TextStyle(color: body, fontWeight: FontWeight.w600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? onPrimary
              : semantic.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : border,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: primary,
        labelColor: primary,
        unselectedLabelColor: semantic.muted,
        dividerColor: border,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
