import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/app/theme_controller.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/navigation/direct_ai_router.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DirectAboutScreen extends ConsumerWidget {
  const DirectAboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreference = ref.watch(themeControllerProvider);
    return ListView(
      key: const Key('direct-about-screen'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        const AppSectionHeader(
          title: 'Giới thiệu & Cài đặt',
          subtitle:
              'Thông tin đề tài, kiến trúc ứng dụng và tùy chọn giao diện.',
        ),
        const SizedBox(height: 18),
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PolypVision',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                'Nghiên cứu phương pháp tích hợp VMamba vào YOLO26n-seg trong '
                'phân đoạn polyp đại trực tràng từ ảnh nội soi.',
              ),
              SizedBox(height: 8),
              Text(
                'Ứng dụng di động phục vụ trình diễn và hỗ trợ đánh giá kết quả nghiên cứu.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _ArchitectureCard(),
        const SizedBox(height: 14),
        const _ResearchModelsCard(),
        const SizedBox(height: 14),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Giao diện', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              RadioGroup<AppThemePreference>(
                groupValue: themePreference,
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(themeControllerProvider.notifier)
                        .setPreference(value);
                  }
                },
                child: Column(
                  children: [
                    for (final preference in AppThemePreference.values)
                      RadioListTile<AppThemePreference>(
                        key: Key('direct-theme-${preference.name}'),
                        value: preference,
                        title: Text(preference.label),
                        secondary: Icon(switch (preference) {
                          AppThemePreference.system =>
                            Icons.settings_brightness,
                          AppThemePreference.light => Icons.light_mode_outlined,
                          AppThemePreference.dark => Icons.dark_mode_outlined,
                        }, semanticLabel: 'Giao diện ${preference.label}'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 14),
          _DebugCard(
            baseUrl: ref.watch(aiServiceConfigProvider).baseUrl,
            serviceStatus: ref
                .watch(aiHealthProvider)
                .when(
                  loading: () => 'Đang kiểm tra',
                  error: (error, stackTrace) => 'Không kết nối',
                  data: (health) => switch (health.status) {
                    'ok' => 'Sẵn sàng',
                    'degraded' => 'Một phần sẵn sàng',
                    _ => 'Không khả dụng',
                  },
                ),
          ),
        ],
        const SizedBox(height: 14),
        const _LegalLinks(),
        const SizedBox(height: 14),
        const _FutureEnhancements(),
        const SizedBox(height: 18),
        const ResearchDisclaimer(),
      ],
    );
  }
}

class _ArchitectureCard extends StatelessWidget {
  const _ArchitectureCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      semanticLabel: 'Kiến trúc Flutter tới FastAPI tới AI models',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kiến trúc mobile',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Flutter')),
              Icon(Icons.arrow_forward, semanticLabel: 'kết nối tới'),
              Chip(label: Text('FastAPI')),
              Icon(Icons.arrow_forward, semanticLabel: 'chạy'),
              Chip(label: Text('AI models')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResearchModelsCard extends StatelessWidget {
  const _ResearchModelsCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hai mô hình', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.model_training_outlined),
            title: Text('YOLO26n-seg'),
            subtitle: Text('Baseline dùng để đối chiếu.'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.hub_outlined),
            title: Text('YOLO26n-seg + VMamba'),
            subtitle: Text('Mô hình nghiên cứu tích hợp khối VMamba.'),
          ),
        ],
      ),
    );
  }
}

class _DebugCard extends StatelessWidget {
  const _DebugCard({required this.baseUrl, required this.serviceStatus});

  final String baseUrl;
  final String serviceStatus;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      semanticLabel: 'Thông tin debug dịch vụ AI',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bug_report_outlined, color: context.appColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'AI base URL\n$baseUrl\n\nTrạng thái service: $serviceStatus',
              key: const Key('direct-debug-ai-base-url'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _LegalLink(
            key: const Key('direct-terms-link'),
            icon: Icons.gavel_outlined,
            label: 'Điều khoản sử dụng',
            route: DirectAiRoutes.terms,
          ),
          const Divider(height: 1),
          _LegalLink(
            key: const Key('direct-privacy-link'),
            icon: Icons.privacy_tip_outlined,
            label: 'Chính sách quyền riêng tư',
            route: DirectAiRoutes.privacy,
          ),
          const Divider(height: 1),
          _LegalLink(
            key: const Key('direct-disclaimer-link'),
            icon: Icons.health_and_safety_outlined,
            label: 'Tuyên bố miễn trừ',
            route: DirectAiRoutes.disclaimer,
          ),
        ],
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.icon,
    required this.label,
    required this.route,
    super.key,
  });

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, semanticLabel: label),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}

class _FutureEnhancements extends StatelessWidget {
  const _FutureEnhancements();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      semanticLabel: 'Mở rộng tương lai chưa có trong phiên bản hiện tại',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mở rộng tương lai',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          Text('Mobile Account & Cloud Sync'),
          SizedBox(height: 4),
          Text(
            'Tài khoản mobile, lịch sử cloud và đồng bộ web-mobile chưa có trong phiên bản hiện tại.',
          ),
        ],
      ),
    );
  }
}
