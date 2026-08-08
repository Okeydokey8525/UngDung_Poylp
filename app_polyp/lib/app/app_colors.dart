import 'package:flutter/material.dart';

abstract final class AppColors {
  static const lightBackground = Color(0xFFFFFFFF);
  static const lightPrimary = Color(0xFF0B6BCB);
  static const lightPrimaryHover = Color(0xFF0758AC);
  static const lightPrimarySoft = Color(0xFFEAF4FF);
  static const lightAccent = Color(0xFF0B9F9A);
  static const lightAccentDark = Color(0xFF087F7B);
  static const lightAccentSoft = Color(0xFFE7F8F6);
  static const lightHeading = Color(0xFF0D2B45);
  static const lightBody = Color(0xFF244158);
  static const lightMuted = Color(0xFF678095);
  static const lightBorder = Color(0xFFDCE8F0);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFF5F9FC);
  static const lightSuccess = Color(0xFF18835B);
  static const lightWarning = Color(0xFFB65C00);
  static const lightDanger = Color(0xFFBD3D49);
  static const lightSuccessSoft = Color(0xFFEEFAF5);
  static const lightWarningSoft = Color(0xFFFFF5E8);
  static const lightDangerSoft = Color(0xFFFFF1F2);
  static const lightInput = Color(0xFFFFFFFF);

  static const darkBackground = Color(0xFF0B1D2A);
  static const darkPrimary = Color(0xFF64B5FF);
  static const darkPrimaryHover = Color(0xFF8AC8FF);
  static const darkPrimarySoft = Color(0xFF142F46);
  static const darkAccent = Color(0xFF43D2C7);
  static const darkAccentDark = Color(0xFF73E2DA);
  static const darkAccentSoft = Color(0xFF123A3D);
  static const darkHeading = Color(0xFFEDF7FF);
  static const darkBody = Color(0xFFD7E6F0);
  static const darkMuted = Color(0xFF9FB5C4);
  static const darkBorder = Color(0xFF294456);
  static const darkSurface = Color(0xFF102635);
  static const darkSurfaceAlt = Color(0xFF142C3B);
  static const darkSuccess = Color(0xFF70D6AA);
  static const darkWarning = Color(0xFFF3B56C);
  static const darkDanger = Color(0xFFFF9AA5);
  static const darkSuccessSoft = Color(0xFF17372E);
  static const darkWarningSoft = Color(0xFF3B2B1D);
  static const darkDangerSoft = Color(0xFF3A2229);
  static const darkInput = Color(0xFF0D2230);

  static const radiusSmall = 10.0;
  static const radiusNormal = 16.0;
  static const radiusLarge = 24.0;
  static const interactiveMinHeight = 44.0;
}

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.heading,
    required this.muted,
    required this.border,
    required this.surfaceAlt,
    required this.input,
    required this.primarySoft,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.successSoft,
    required this.warningSoft,
    required this.dangerSoft,
  });

  factory AppSemanticColors.light() => const AppSemanticColors(
    heading: AppColors.lightHeading,
    muted: AppColors.lightMuted,
    border: AppColors.lightBorder,
    surfaceAlt: AppColors.lightSurfaceAlt,
    input: AppColors.lightInput,
    primarySoft: AppColors.lightPrimarySoft,
    accent: AppColors.lightAccent,
    accentSoft: AppColors.lightAccentSoft,
    success: AppColors.lightSuccess,
    warning: AppColors.lightWarning,
    danger: AppColors.lightDanger,
    successSoft: AppColors.lightSuccessSoft,
    warningSoft: AppColors.lightWarningSoft,
    dangerSoft: AppColors.lightDangerSoft,
  );

  factory AppSemanticColors.dark() => const AppSemanticColors(
    heading: AppColors.darkHeading,
    muted: AppColors.darkMuted,
    border: AppColors.darkBorder,
    surfaceAlt: AppColors.darkSurfaceAlt,
    input: AppColors.darkInput,
    primarySoft: AppColors.darkPrimarySoft,
    accent: AppColors.darkAccent,
    accentSoft: AppColors.darkAccentSoft,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    danger: AppColors.darkDanger,
    successSoft: AppColors.darkSuccessSoft,
    warningSoft: AppColors.darkWarningSoft,
    dangerSoft: AppColors.darkDangerSoft,
  );

  @override
  AppSemanticColors copyWith({
    Color? heading,
    Color? muted,
    Color? border,
    Color? surfaceAlt,
    Color? input,
    Color? primarySoft,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? danger,
    Color? successSoft,
    Color? warningSoft,
    Color? dangerSoft,
  }) {
    return AppSemanticColors(
      heading: heading ?? this.heading,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      input: input ?? this.input,
      primarySoft: primarySoft ?? this.primarySoft,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      successSoft: successSoft ?? this.successSoft,
      warningSoft: warningSoft ?? this.warningSoft,
      dangerSoft: dangerSoft ?? this.dangerSoft,
    );
  }

  @override
  AppSemanticColors lerp(covariant AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      heading: Color.lerp(heading, other.heading, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      input: Color.lerp(input, other.input, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
    );
  }

  final Color heading;
  final Color muted;
  final Color border;
  final Color surfaceAlt;
  final Color input;
  final Color primarySoft;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color successSoft;
  final Color warningSoft;
  final Color dangerSoft;
}

extension AppThemeColors on BuildContext {
  AppSemanticColors get appColors =>
      Theme.of(this).extension<AppSemanticColors>()!;
}
