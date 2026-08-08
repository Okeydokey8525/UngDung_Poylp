import 'dart:math' as math;

import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/dashboard/dashboard_models.dart';
import 'package:app_polyp/features/dashboard/dashboard_state.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_empty_state.dart';
import 'package:app_polyp/shared/widgets/app_error_state.dart';
import 'package:app_polyp/shared/widgets/app_loading_view.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(dashboardControllerProvider.notifier).load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardControllerProvider);
    if (state.status == DashboardStatus.initial ||
        state.status == DashboardStatus.loading) {
      return const AppLoadingView(message: 'Đang tải thống kê hoạt động…');
    }
    if (state.status == DashboardStatus.error) {
      return AppErrorState(
        title: 'Không thể tải dashboard',
        message: state.message ?? 'Đã xảy ra lỗi, vui lòng thử lại.',
        onRetry: () =>
            ref.read(dashboardControllerProvider.notifier).load(force: true),
      );
    }

    final dashboard = state.dashboard;
    if (dashboard == null) {
      return const AppLoadingView();
    }
    if (state.status == DashboardStatus.empty) {
      return RefreshIndicator(
        onRefresh: ref.read(dashboardControllerProvider.notifier).refresh,
        child: ListView(
          key: const Key('dashboard-empty'),
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const AppSectionHeader(
              title: 'Tổng quan hoạt động',
              subtitle: 'Dữ liệu sử dụng đã lưu của tài khoản hiện tại.',
            ),
            const SizedBox(height: 32),
            AppEmptyState(
              title: 'Chưa có hoạt động',
              message:
                  'Khi bạn thực hiện phân tích hoặc so sánh, các thống kê '
                  'sẽ xuất hiện tại đây.',
              icon: Icons.analytics_outlined,
              action: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go(AppRoutes.diagnosis),
                    icon: const Icon(Icons.image_search),
                    label: const Text('Phân tích'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.comparison),
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('So sánh'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Disclaimer(text: dashboard.disclaimer),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: ref.read(dashboardControllerProvider.notifier).refresh,
      child: ListView(
        key: const Key('dashboard-data'),
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const AppSectionHeader(
            title: 'Tổng quan hoạt động',
            subtitle: 'Dữ liệu sử dụng đã lưu của tài khoản hiện tại.',
          ),
          if (state.status == DashboardStatus.refreshing) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(key: Key('dashboard-refreshing')),
          ],
          if (state.refreshMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              state.refreshMessage!,
              key: const Key('dashboard-refresh-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          _KpiGrid(summary: dashboard.summary),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final daily = _DailyUsageChart(days: dashboard.dailyUsage);
              final distributions = Column(
                children: [
                  _DistributionCard(
                    title: 'Phân bố họ mô hình',
                    firstLabel: 'Baseline',
                    firstValue: dashboard.modelUsage.baseline,
                    secondLabel: 'VMamba',
                    secondValue: dashboard.modelUsage.vmamba,
                    firstColor: Theme.of(context).colorScheme.primary,
                    secondColor: context.appColors.warning,
                  ),
                  const SizedBox(height: 12),
                  _DistributionCard(
                    title: 'Kết quả dự đoán',
                    firstLabel: 'Phát hiện',
                    firstValue: dashboard.predictionUsage.detected,
                    secondLabel: 'Không phát hiện',
                    secondValue: dashboard.predictionUsage.notDetected,
                    firstColor: context.appColors.success,
                    secondColor: context.appColors.muted,
                  ),
                ],
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  children: [daily, const SizedBox(height: 12), distributions],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: daily),
                  const SizedBox(width: 12),
                  Expanded(child: distributions),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          _RecentActivities(activities: dashboard.recentActivities),
          const SizedBox(height: 20),
          _Disclaimer(text: dashboard.disclaimer),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Tổng phân tích', summary.singleAnalysisCount, Icons.analytics_outlined),
      ('Phiên so sánh', summary.comparisonSessionCount, Icons.compare_arrows),
      ('Tổng inference', summary.totalInferenceCount, Icons.memory_outlined),
      ('Phát hiện', summary.detectedCount, Icons.search_outlined),
      ('Tổng mask', summary.totalMaskCount, Icons.layers_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 840
            ? 3
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _KpiCard(
                  label: item.$1,
                  value: _formatInt(item.$2),
                  icon: item.$3,
                ),
              ),
            SizedBox(
              width: width,
              child: _KpiCard(
                label: 'Thời gian AI trung bình',
                value: '${_formatDecimal(summary.averageProcessingTimeMs)} ms',
                icon: Icons.timer_outlined,
              ),
            ),
            SizedBox(
              width: width,
              child: _KpiCard(
                label: 'Mô hình dùng nhiều nhất',
                value: summary.mostUsedModel ?? 'Chưa có dữ liệu',
                icon: Icons.model_training_outlined,
                compactValue: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    this.compactValue = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool compactValue;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      semanticLabel: '$label: $value',
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: compactValue ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: compactValue
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.headlineSmall,
                ),
                Text(label, style: TextStyle(color: context.appColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyUsageChart extends StatelessWidget {
  const _DailyUsageChart({required this.days});

  final List<DailyUsage> days;

  @override
  Widget build(BuildContext context) {
    final visible = days.length <= 7 ? days : days.sublist(days.length - 7);
    final maximum = visible.fold<int>(
      0,
      (current, day) => math.max(current, day.count),
    );
    return AppCard(
      semanticLabel:
          'Hoạt động 7 ngày: ${visible.map((day) => '${day.count}').join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hoạt động 7 ngày',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in visible)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        children: [
                          Text(
                            _formatInt(day.count),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: maximum == 0
                                    ? 0
                                    : day.count / maximum,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${day.date.day}/${day.date.month}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({
    required this.title,
    required this.firstLabel,
    required this.firstValue,
    required this.secondLabel,
    required this.secondValue,
    required this.firstColor,
    required this.secondColor,
  });

  final String title;
  final String firstLabel;
  final int firstValue;
  final String secondLabel;
  final int secondValue;
  final Color firstColor;
  final Color secondColor;

  @override
  Widget build(BuildContext context) {
    final total = firstValue + secondValue;
    final firstRatio = total == 0 ? 0.0 : firstValue / total;
    return AppCard(
      semanticLabel:
          '$title: $firstLabel $firstValue, $secondLabel $secondValue',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                  flex: total == 0 ? 1 : math.max(1, firstValue),
                  child: Container(height: 12, color: firstColor),
                ),
                Expanded(
                  flex: total == 0 ? 1 : math.max(1, secondValue),
                  child: Container(height: 12, color: secondColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$firstLabel: ${_formatInt(firstValue)} '
            '(${_formatPercent(firstRatio)})',
          ),
          Text(
            '$secondLabel: ${_formatInt(secondValue)} '
            '(${_formatPercent(total == 0 ? 0 : secondValue / total)})',
          ),
        ],
      ),
    );
  }
}

class _RecentActivities extends StatelessWidget {
  const _RecentActivities({required this.activities});

  final List<RecentActivity> activities;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hoạt động gần đây',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (activities.isEmpty)
            Text(
              'Chưa có hoạt động gần đây.',
              style: TextStyle(color: context.appColors.muted),
            )
          else
            for (var index = 0; index < activities.length; index++) ...[
              _RecentActivityTile(activity: activities[index]),
              if (index < activities.length - 1) const Divider(),
            ],
        ],
      ),
    );
  }
}

class _RecentActivityTile extends StatelessWidget {
  const _RecentActivityTile({required this.activity});

  final RecentActivity activity;

  @override
  Widget build(BuildContext context) {
    final comparison = activity.type == RecentActivityType.comparison;
    final status = activity.detected
        ? 'Phát hiện · ${_formatPercent(activity.confidence)}'
        : 'Không phát hiện';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Icon(comparison ? Icons.compare_arrows : Icons.image_search),
      ),
      title: Text(activity.fileName),
      subtitle: Text(
        '${comparison ? 'So sánh' : 'Phân tích'} · ${activity.modelType}\n'
        '$status · ${activity.maskCount} mask · '
        '${_formatDecimal(activity.processingTimeMs)} ms'
        '${activity.createdAt == null ? '' : '\n${_formatDateTime(activity.createdAt!)}'}',
      ),
      isThreeLine: true,
      onTap: comparison && activity.comparisonGroupId?.isNotEmpty == true
          ? () => context.push(
              AppRoutes.comparisonResult(activity.comparisonGroupId!),
            )
          : !comparison && activity.id.isNotEmpty
          ? () => context.push(AppRoutes.diagnosisResult(activity.id))
          : null,
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      semanticLabel: text,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.science_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

String _formatInt(int value) {
  final digits = value.toString();
  return digits.replaceAllMapped(
    RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
}

String _formatDecimal(double value) =>
    value.toStringAsFixed(1).replaceAll('.', ',');

String _formatPercent(double ratio) =>
    '${(ratio.clamp(0, 1) * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
