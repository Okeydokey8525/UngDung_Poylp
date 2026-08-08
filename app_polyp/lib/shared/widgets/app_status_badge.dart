import 'package:app_polyp/app/app_colors.dart';
import 'package:flutter/material.dart';

enum AppStatus { detected, clear, warning, information }

class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge({required this.status, required this.text, super.key});

  final AppStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (foreground, background, icon) = switch (status) {
      AppStatus.detected => (
        colors.warning,
        colors.warningSoft,
        Icons.warning_amber_rounded,
      ),
      AppStatus.clear => (
        colors.success,
        colors.successSoft,
        Icons.check_circle_outline,
      ),
      AppStatus.warning => (
        colors.danger,
        colors.dangerSoft,
        Icons.error_outline,
      ),
      AppStatus.information => (
        Theme.of(context).colorScheme.primary,
        colors.primarySoft,
        Icons.info_outline,
      ),
    };

    return Semantics(
      label: '$text, trạng thái có biểu tượng',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppColors.radiusSmall),
          border: Border.all(color: foreground.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
