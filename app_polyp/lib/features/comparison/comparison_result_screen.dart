import 'package:app_polyp/features/comparison/comparison_controller.dart';
import 'package:app_polyp/features/comparison/comparison_models.dart';
import 'package:app_polyp/features/comparison/comparison_state.dart';
import 'package:app_polyp/features/diagnosis/authenticated_image.dart';
import 'package:app_polyp/features/diagnosis/fullscreen_image_screen.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_error_state.dart';
import 'package:app_polyp/shared/widgets/app_loading_view.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:app_polyp/shared/widgets/app_status_badge.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ComparisonResultScreen extends ConsumerStatefulWidget {
  const ComparisonResultScreen({
    required this.comparisonGroupId,
    super.key,
    this.initialResult,
  });

  final String comparisonGroupId;
  final ComparisonResult? initialResult;

  @override
  ConsumerState<ComparisonResultScreen> createState() =>
      _ComparisonResultScreenState();
}

class _ComparisonResultScreenState
    extends ConsumerState<ComparisonResultScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref
          .read(comparisonControllerProvider.notifier)
          .openResult(
            widget.comparisonGroupId,
            initialResult: widget.initialResult,
          ),
    );
  }

  @override
  void didUpdateWidget(covariant ComparisonResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comparisonGroupId != widget.comparisonGroupId) {
      Future<void>.microtask(
        () => ref
            .read(comparisonControllerProvider.notifier)
            .openResult(
              widget.comparisonGroupId,
              initialResult: widget.initialResult,
            ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(comparisonControllerProvider);
    final result = state.result?.comparisonGroupId == widget.comparisonGroupId
        ? state.result
        : null;
    if (result == null &&
        (state.status == ComparisonStatus.idle ||
            state.status == ComparisonStatus.processing)) {
      return const AppLoadingView(message: 'Đang tải phiên so sánh…');
    }
    if (result == null) {
      return AppErrorState(
        title: 'Không thể tải phiên so sánh',
        message: state.message ?? 'Không tìm thấy phiên so sánh.',
        onRetry: () => ref
            .read(comparisonControllerProvider.notifier)
            .openResult(widget.comparisonGroupId),
      );
    }
    return _ComparisonContent(result: result, state: state);
  }
}

class _ComparisonContent extends ConsumerWidget {
  const _ComparisonContent({required this.result, required this.state});

  final ComparisonResult result;
  final ComparisonState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppSectionHeader(title: 'Kết quả so sánh', subtitle: result.fileName),
        const SizedBox(height: 18),
        _OriginalImage(result: result),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            // The surrounding page contributes 40 px of horizontal padding,
            // so 800 px here corresponds to the 840 px tablet breakpoint.
            if (constraints.maxWidth >= 800) {
              return Row(
                key: const Key('comparison-tablet-split'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _ModelPanel(
                      heading: 'Baseline',
                      result: result.baseline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ModelPanel(
                      heading: 'VMamba',
                      result: result.vmamba,
                    ),
                  ),
                ],
              );
            }
            return DefaultTabController(
              length: 2,
              child: Column(
                key: const Key('comparison-phone-tabs'),
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Baseline'),
                      Tab(text: 'VMamba'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 610,
                    child: TabBarView(
                      children: [
                        SingleChildScrollView(
                          child: _ModelPanel(
                            heading: 'Baseline',
                            result: result.baseline,
                          ),
                        ),
                        SingleChildScrollView(
                          child: _ModelPanel(
                            heading: 'VMamba',
                            result: result.vmamba,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 18),
        AppCard(
          semanticLabel:
              'Tổng thời gian hai lượt inference tuần tự: '
              '${result.totalProcessingTimeMs.toStringAsFixed(1)} mili giây',
          child: Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _Metric(label: 'Thời điểm', value: _dateTime(result.createdAt)),
              _Metric(
                label: 'Tổng hai lượt inference tuần tự',
                value: '${result.totalProcessingTimeMs.toStringAsFixed(1)} ms',
              ),
            ],
          ),
        ),
        if (state.message != null) ...[
          const SizedBox(height: 12),
          Text(
            state.message!,
            key: const Key('comparison-result-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: state.status == ComparisonStatus.deleting
                  ? null
                  : () {
                      ref
                          .read(comparisonControllerProvider.notifier)
                          .compareAnother();
                      context.go(AppRoutes.comparison);
                    },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('So sánh ảnh khác'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.dashboard),
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Về dashboard'),
            ),
            OutlinedButton.icon(
              key: const Key('delete-comparison-button'),
              onPressed: state.status == ComparisonStatus.deleting
                  ? null
                  : () => _confirmDelete(context, ref),
              icon: state.status == ComparisonStatus.deleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: const Text('Xóa phiên so sánh'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const ResearchDisclaimer(key: Key('comparison-result-disclaimer')),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa phiên so sánh?'),
        content: const Text(
          'Ảnh gốc, hai overlay và toàn bộ lịch sử của phiên này sẽ bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm-delete-comparison'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final deleted = await ref
        .read(comparisonControllerProvider.notifier)
        .deleteCurrent();
    if (deleted && context.mounted) {
      context.go(AppRoutes.comparison);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xóa phiên so sánh.')));
    }
  }
}

class _OriginalImage extends StatelessWidget {
  const _OriginalImage({required this.result});

  final ComparisonResult result;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ảnh gốc dùng chung',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: AuthenticatedImage(
              key: const Key('comparison-original-image'),
              url: result.originalImageUrl,
              semanticLabel: 'Ảnh gốc dùng chung cho hai mô hình',
            ),
          ),
          TextButton.icon(
            key: const Key('comparison-original-fullscreen'),
            onPressed: () => _openFullscreen(
              context,
              result.originalImageUrl,
              'Ảnh gốc dùng chung',
            ),
            icon: const Icon(Icons.fullscreen),
            label: const Text('Xem ảnh gốc toàn màn hình'),
          ),
        ],
      ),
    );
  }
}

class _ModelPanel extends StatelessWidget {
  const _ModelPanel({required this.heading, required this.result});

  final String heading;
  final ComparisonModelResult result;

  @override
  Widget build(BuildContext context) {
    final keyPrefix = heading.toLowerCase();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(heading, style: Theme.of(context).textTheme.titleLarge),
          Text(result.modelType),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: AppStatusBadge(
              status: result.detected ? AppStatus.detected : AppStatus.clear,
              text: result.detected
                  ? 'Có vùng được đánh dấu'
                  : 'Không phát hiện',
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: AuthenticatedImage(
              key: Key('$keyPrefix-overlay-image'),
              url: result.resultImageUrl,
              semanticLabel: 'Overlay phân đoạn $heading',
            ),
          ),
          TextButton.icon(
            key: Key('$keyPrefix-fullscreen'),
            onPressed: () => _openFullscreen(
              context,
              result.resultImageUrl,
              'Overlay $heading',
            ),
            icon: const Icon(Icons.fullscreen),
            label: Text('Xem $heading toàn màn hình'),
          ),
          Text('Nhóm mô hình: ${result.modelCategory}'),
          if (result.label != null) Text('Nhãn: ${result.label}'),
          if (result.detected)
            Text(
              'Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%',
            ),
          Text('Số mask: ${result.maskCount}'),
          Text(
            'Thời gian xử lý: ${result.processingTimeMs.toStringAsFixed(1)} ms',
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 240,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

void _openFullscreen(BuildContext context, String url, String title) {
  context.push(
    AppRoutes.diagnosisImage,
    extra: AuthenticatedImageArguments(url: url, title: title),
  );
}

String _dateTime(DateTime? value) {
  if (value == null) return 'Không xác định';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
