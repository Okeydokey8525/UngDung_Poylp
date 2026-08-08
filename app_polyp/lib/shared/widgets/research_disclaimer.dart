import 'package:app_polyp/app/app_colors.dart';
import 'package:flutter/material.dart';

class ResearchDisclaimer extends StatelessWidget {
  const ResearchDisclaimer({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Semantics(
      container: true,
      label: 'Lưu ý nghiên cứu và y khoa',
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: colors.warningSoft,
          borderRadius: BorderRadius.circular(AppColors.radiusNormal),
          border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: colors.warning),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '''Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, không thay thế chẩn đoán hoặc quyết định chuyên môn của bác sĩ.''',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
