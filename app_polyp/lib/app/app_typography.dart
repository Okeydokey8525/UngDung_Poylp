import 'package:flutter/material.dart';

abstract final class AppTypography {
  static TextTheme textTheme(Color body, Color heading) {
    return TextTheme(
      displaySmall: TextStyle(
        color: heading,
        fontSize: 34,
        fontWeight: FontWeight.w800,
        height: 1.15,
      ),
      headlineSmall: TextStyle(
        color: heading,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleLarge: TextStyle(
        color: heading,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: heading,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: body, fontSize: 16, height: 1.55),
      bodyMedium: TextStyle(color: body, fontSize: 14, height: 1.5),
      labelLarge: TextStyle(
        color: body,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
