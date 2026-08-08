import 'package:app_polyp/features/diagnosis/authenticated_image.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_state.dart';
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

class DiagnosisResultScreen extends ConsumerStatefulWidget {
  const DiagnosisResultScreen({
    required this.id,
    super.key,
    this.initialResult,
  });

  final String id;
  final DiagnosisResult? initialResult;

  @override
  ConsumerState<DiagnosisResultScreen> createState() =>
      _DiagnosisResultScreenState();
}

class _DiagnosisResultScreenState extends ConsumerState<DiagnosisResultScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref
          .read(diagnosisControllerProvider.notifier)
          .openResult(widget.id, initialResult: widget.initialResult),
    );
  }

  @override
  void didUpdateWidget(covariant DiagnosisResultScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      Future<void>.microtask(
        () => ref
            .read(diagnosisControllerProvider.notifier)
            .openResult(widget.id, initialResult: widget.initialResult),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(diagnosisControllerProvider);
    final result = state.result?.id == widget.id ? state.result : null;
    if (result == null &&
        (state.status == DiagnosisStatus.processing ||
            state.status == DiagnosisStatus.idle)) {
      return const AppLoadingView(message: 'Đang tải kết quả phân tích…');
    }
    if (result == null) {
      return AppErrorState(
        title: 'Không thể tải kết quả',
        message: state.message ?? 'Không tìm thấy kết quả phân tích.',
        onRetry: () => ref
            .read(diagnosisControllerProvider.notifier)
            .openResult(widget.id),
      );
    }
    return _ResultContent(result: result, state: state);
  }
}

class _ResultContent extends ConsumerWidget {
  const _ResultContent({required this.result, required this.state});

  final DiagnosisResult result;
  final DiagnosisState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppSectionHeader(
          title: 'Kết quả phân đoạn',
          subtitle: result.fileName,
          action: AppStatusBadge(
            status: result.detected ? AppStatus.detected : AppStatus.clear,
            text: result.detected ? 'Có vùng được đánh dấu' : 'Không phát hiện',
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final original = _ResultImageCard(
              title: 'Ảnh gốc',
              url: result.originalImageUrl,
              fullscreenKey: const Key('original-fullscreen'),
            );
            final overlay = _ResultImageCard(
              title: 'Overlay phân đoạn',
              url: result.resultImageUrl,
              fullscreenKey: const Key('result-fullscreen'),
            );
            if (constraints.maxWidth < 720) {
              return Column(
                children: [original, const SizedBox(height: 12), overlay],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: original),
                const SizedBox(width: 12),
                Expanded(child: overlay),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        AppCard(
          child: Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _Metric(label: 'Mô hình', value: result.modelType),
              _Metric(label: 'Nhóm mô hình', value: result.modelCategory),
              _Metric(
                label: 'Trạng thái',
                value: result.detected
                    ? 'Có vùng được đánh dấu'
                    : 'Không phát hiện',
              ),
              if (result.label != null)
                _Metric(label: 'Nhãn', value: result.label!),
              if (result.detected)
                _Metric(
                  label: 'Confidence',
                  value: '${(result.confidence * 100).toStringAsFixed(1)}%',
                ),
              _Metric(label: 'Số mask', value: '${result.maskCount}'),
              _Metric(
                label: 'Thời gian xử lý',
                value: '${result.processingTimeMs.toStringAsFixed(1)} ms',
              ),
              _Metric(
                label: 'Thời điểm',
                value: _formatDateTime(result.createdAt),
              ),
            ],
          ),
        ),
        if (state.message != null) ...[
          const SizedBox(height: 12),
          Text(
            state.message!,
            key: const Key('diagnosis-result-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: state.status == DiagnosisStatus.deleting
                  ? null
                  : () {
                      ref
                          .read(diagnosisControllerProvider.notifier)
                          .analyzeAnother();
                      context.go(AppRoutes.diagnosis);
                    },
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Phân tích ảnh khác'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.dashboard),
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Về dashboard'),
            ),
            OutlinedButton.icon(
              key: const Key('delete-diagnosis-button'),
              onPressed: state.status == DiagnosisStatus.deleting
                  ? null
                  : () => _confirmDelete(context, ref),
              icon: state.status == DiagnosisStatus.deleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: const Text('Xóa kết quả'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const ResearchDisclaimer(key: Key('result-disclaimer')),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa kết quả?'),
        content: const Text(
          'Bản ghi, ảnh gốc và overlay sẽ bị xóa khỏi hệ thống.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('confirm-delete-diagnosis'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final deleted = await ref
        .read(diagnosisControllerProvider.notifier)
        .deleteCurrent();
    if (deleted && context.mounted) {
      context.go(AppRoutes.diagnosis);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa kết quả phân tích.')),
      );
    }
  }
}

class _ResultImageCard extends StatelessWidget {
  const _ResultImageCard({
    required this.title,
    required this.url,
    required this.fullscreenKey,
  });

  final String title;
  final String url;
  final Key fullscreenKey;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: AuthenticatedImage(url: url, semanticLabel: title),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: fullscreenKey,
            onPressed: () => context.push(
              AppRoutes.diagnosisImage,
              extra: AuthenticatedImageArguments(url: url, title: title),
            ),
            icon: const Icon(Icons.fullscreen),
            label: const Text('Xem toàn màn hình'),
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
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
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
}

String _formatDateTime(DateTime? value) {
  if (value == null) return 'Không xác định';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
