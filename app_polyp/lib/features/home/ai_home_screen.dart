import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/home/widgets/ai_model_card.dart';
import 'package:app_polyp/features/home/widgets/ai_service_status_card.dart';
import 'package:app_polyp/navigation/direct_ai_router.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AiHomeScreen extends ConsumerWidget {
  const AiHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(aiHealthProvider);
    final models = ref.watch(aiModelsProvider);
    return ListView(
      key: const Key('ai-home-screen'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const _Hero(),
        const SizedBox(height: 20),
        const AppSectionHeader(
          title: 'Trạng thái dịch vụ AI',
          subtitle: 'Kết nối trực tiếp tới FastAPI, không cần tài khoản.',
        ),
        const SizedBox(height: 12),
        AiServiceStatusCard(
          health: health,
          onRefresh: () => ref.invalidate(aiHealthProvider),
        ),
        const SizedBox(height: 24),
        const AppSectionHeader(
          title: 'Mô hình nghiên cứu',
          subtitle:
              'Trạng thái sẵn sàng được cung cấp trực tiếp bởi dịch vụ AI.',
        ),
        const SizedBox(height: 12),
        _ModelsSection(
          models: models,
          onRetry: () => ref.invalidate(aiModelsProvider),
        ),
        const SizedBox(height: 24),
        _Actions(
          onAnalyze: () => context.go(DirectAiRoutes.analyze),
          onCompare: () => context.go(DirectAiRoutes.compare),
        ),
        const SizedBox(height: 24),
        const _QuickGuide(),
        const SizedBox(height: 20),
        const ResearchDisclaimer(),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      header: true,
      label: 'PolypVision, phân đoạn polyp đại trực tràng từ ảnh nội soi',
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.primaryContainer, context.appColors.accentSoft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          border: Border.all(color: context.appColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.biotech_outlined, size: 38, color: scheme.primary),
            const SizedBox(height: 14),
            Text(
              'PolypVision',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Phân đoạn polyp đại trực tràng từ ảnh nội soi',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text(
              'Ứng dụng nghiên cứu sử dụng YOLO26n-seg và mô hình tích hợp VMamba.',
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelsSection extends StatelessWidget {
  const _ModelsSection({required this.models, required this.onRetry});

  final AsyncValue<AiModelsResponse> models;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return models.when(
      loading: () => AppCard(
        child: Semantics(
          liveRegion: true,
          label: 'Đang tải danh sách mô hình',
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 14),
              Expanded(child: Text('Đang tải danh sách mô hình…')),
            ],
          ),
        ),
      ),
      error: (error, stackTrace) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Không thể tải danh sách mô hình',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            const Text('Dịch vụ AI chưa trả về danh sách mô hình hợp lệ.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('models-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
      data: (value) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 2 : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final model in value.models)
                SizedBox(
                  width: width,
                  child: AiModelCard(model: model),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onAnalyze, required this.onCompare});

  final VoidCallback onAnalyze;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            key: const Key('home-analyze-cta'),
            onPressed: onAnalyze,
            icon: const Icon(Icons.image_search),
            label: const Text('Phân tích ảnh'),
          ),
          OutlinedButton.icon(
            key: const Key('home-compare-cta'),
            onPressed: onCompare,
            icon: const Icon(Icons.compare_arrows),
            label: const Text('So sánh mô hình'),
          ),
        ],
      ),
    );
  }
}

class _QuickGuide extends StatelessWidget {
  const _QuickGuide();

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('1', 'Chọn ảnh nội soi'),
      ('2', 'Chọn mô hình'),
      ('3', 'Xem vùng polyp được phân đoạn'),
    ];
    return AppCard(
      semanticLabel: 'Hướng dẫn sử dụng gồm ba bước',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quy trình dự kiến',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final step in steps)
                Chip(
                  avatar: CircleAvatar(child: Text(step.$1)),
                  label: Text(step.$2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
