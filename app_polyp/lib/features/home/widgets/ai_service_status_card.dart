import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/core/network/ai_api_exception.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiServiceStatusCard extends StatelessWidget {
  const AiServiceStatusCard({
    required this.health,
    required this.onRefresh,
    super.key,
  });

  final AsyncValue<AiHealthResponse> health;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      semanticLabel: 'Trạng thái dịch vụ AI',
      child: health.when(
        loading: () => Semantics(
          liveRegion: true,
          label: 'Đang kiểm tra trạng thái dịch vụ AI',
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 14),
              Expanded(child: Text('Đang kiểm tra dịch vụ AI…')),
            ],
          ),
        ),
        error: (error, stackTrace) =>
            _HealthError(error: error, onRefresh: onRefresh),
        data: (value) => _HealthData(value: value, onRefresh: onRefresh),
      ),
    );
  }
}

class _HealthData extends StatelessWidget {
  const _HealthData({required this.value, required this.onRefresh});

  final AiHealthResponse value;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (
      title,
      detail,
      icon,
      foreground,
      background,
    ) = switch (value.status) {
      'ok' when value.ready => (
        'Dịch vụ AI đã sẵn sàng',
        '${value.readyModels}/${value.totalModels} mô hình sẵn sàng · ${value.device}',
        Icons.check_circle_outline,
        colors.success,
        colors.successSoft,
      ),
      'degraded' => (
        'Một số mô hình chưa sẵn sàng',
        '${value.readyModels}/${value.totalModels} mô hình sẵn sàng · ${value.device}',
        Icons.warning_amber_rounded,
        colors.warning,
        colors.warningSoft,
      ),
      _ => (
        'Dịch vụ AI hiện không khả dụng',
        'Hiện có ${value.readyModels}/${value.totalModels} mô hình sẵn sàng.',
        Icons.cloud_off_outlined,
        colors.danger,
        colors.dangerSoft,
      ),
    };
    return Semantics(
      liveRegion: true,
      label: '$title. $detail',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
            ),
            child: Icon(icon, color: foreground, semanticLabel: title),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(detail, style: TextStyle(color: colors.muted)),
              ],
            ),
          ),
          IconButton(
            key: const Key('health-refresh'),
            onPressed: onRefresh,
            tooltip: 'Làm mới trạng thái dịch vụ AI',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _HealthError extends StatelessWidget {
  const _HealthError({required this.error, required this.onRefresh});

  final Object error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final invalidResponse =
        error is AiApiException &&
        (error as AiApiException).kind == AiFailureKind.invalidResponse;
    final title = invalidResponse
        ? 'Phản hồi dịch vụ AI không hợp lệ'
        : 'Không thể kết nối dịch vụ AI';
    return Semantics(
      liveRegion: true,
      label: title,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            color: context.appColors.danger,
            semanticLabel: 'Lỗi kết nối dịch vụ AI',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                const Text('Kiểm tra kết nối rồi thử lại.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('health-error-retry'),
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
