import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/comparison/direct_comparison_controller.dart';
import 'package:app_polyp/features/comparison/direct_comparison_state.dart';
import 'package:app_polyp/features/home/widgets/ai_model_card.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:app_polyp/shared/widgets/medical_image_picker_card.dart';
import 'package:app_polyp/shared/widgets/memory_image_card.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ComparisonPanel { baseline, vmamba }

class DirectComparisonScreen extends ConsumerStatefulWidget {
  const DirectComparisonScreen({super.key});

  @override
  ConsumerState<DirectComparisonScreen> createState() =>
      _DirectComparisonScreenState();
}

class _DirectComparisonScreenState
    extends ConsumerState<DirectComparisonScreen> {
  String? _lastModelsRequestId;
  _ComparisonPanel _mobilePanel = _ComparisonPanel.baseline;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(directComparisonControllerProvider);
    final controller = ref.read(directComparisonControllerProvider.notifier);
    final models = ref.watch(aiModelsProvider);
    final modelData = models.asData?.value;
    final bothModelsReady =
        modelData != null &&
        modelData.models.length == 2 &&
        modelData.models.every((model) => model.ready);

    models.whenData((value) {
      if (_lastModelsRequestId == value.requestId) return;
      _lastModelsRequestId = value.requestId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.synchronizeModelReadiness(
            value.models.length == 2 &&
                value.models.every((model) => model.ready),
          );
        }
      });
    });

    return ListView(
      key: const Key('direct-comparison-screen'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        AppSectionHeader(
          title: state.hasResult
              ? 'Kết quả so sánh mô hình'
              : 'So sánh mô hình',
          subtitle: state.hasResult
              ? state.image?.name ?? 'Ảnh nội soi'
              : 'Chạy cùng một ảnh qua Baseline và VMamba để đối chiếu kết quả.',
        ),
        const SizedBox(height: 18),
        if (state.hasResult)
          _ComparisonResultView(
            state: state,
            mobilePanel: _mobilePanel,
            onMobilePanelChanged: (value) =>
                setState(() => _mobilePanel = value),
            onCompareAgain: () =>
                controller.compare(bothModelsReady: bothModelsReady),
            onPickAnother: () =>
                controller.pickImage(bothModelsReady: bothModelsReady),
            onReset: controller.reset,
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final imageCard = MedicalImagePickerCard(
                image: state.image,
                onPick: state.isBusy
                    ? null
                    : () => controller.pickImage(
                        bothModelsReady: bothModelsReady,
                      ),
                onRemove: state.isBusy || state.image == null
                    ? null
                    : controller.removeImage,
                pickButtonKey: const Key('direct-comparison-pick-image'),
                removeButtonKey: const Key('direct-comparison-remove-image'),
                previewKey: const Key('direct-comparison-image-preview'),
                fileNameKey: const Key('direct-comparison-image-name'),
              );
              final modelCards = _ComparisonModels(
                models: models,
                onRetry: () => ref.invalidate(aiModelsProvider),
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [imageCard, const SizedBox(height: 16), modelCards],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: imageCard),
                  const SizedBox(width: 16),
                  Expanded(child: modelCards),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _ComparisonControls(
            state: state,
            bothModelsReady: bothModelsReady,
            onCompare: () =>
                controller.compare(bothModelsReady: bothModelsReady),
            onCancel: controller.cancel,
            onPickAnother: () =>
                controller.pickImage(bothModelsReady: bothModelsReady),
            onReset: controller.reset,
          ),
          const SizedBox(height: 16),
          const AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.privacy_tip_outlined),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ảnh được gửi đến dịch vụ AI đã cấu hình để xử lý và '
                    'không được ứng dụng lưu vào lịch sử.',
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        const ResearchDisclaimer(key: Key('direct-comparison-disclaimer')),
      ],
    );
  }
}

class _ComparisonModels extends StatelessWidget {
  const _ComparisonModels({required this.models, required this.onRetry});

  final AsyncValue<AiModelsResponse> models;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      semanticLabel: 'Hai mô hình dùng để so sánh',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hai mô hình đối chiếu',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          models.when(
            loading: () => Semantics(
              liveRegion: true,
              label: 'Đang tải hai mô hình so sánh',
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Đang tải hai mô hình…')),
                ],
              ),
            ),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Không thể tải hai mô hình.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('comparison-models-retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
            data: (value) {
              final bothReady =
                  value.models.length == 2 &&
                  value.models.every((model) => model.ready);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!bothReady) ...[
                    const Text(
                      'Cả hai mô hình phải sẵn sàng trước khi chạy so sánh.',
                      key: Key('direct-comparison-models-not-ready'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('comparison-models-retry'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (var index = 0; index < value.models.length; index++) ...[
                    AiModelCard(model: value.models[index], compact: true),
                    if (index != value.models.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ComparisonControls extends StatelessWidget {
  const _ComparisonControls({
    required this.state,
    required this.bothModelsReady,
    required this.onCompare,
    required this.onCancel,
    required this.onPickAnother,
    required this.onReset,
  });

  final DirectComparisonState state;
  final bool bothModelsReady;
  final VoidCallback onCompare;
  final VoidCallback onCancel;
  final VoidCallback onPickAnother;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final canCompare = state.image != null && bothModelsReady && !state.isBusy;
    final disabledReason = state.image == null
        ? 'Hãy chọn một ảnh hợp lệ trước khi so sánh.'
        : !bothModelsReady
        ? 'Cả hai mô hình phải sẵn sàng trước khi so sánh.'
        : null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (disabledReason != null && !state.isBusy)
            Text(disabledReason, key: const Key('comparison-disabled-reason')),
          if (state.status == DirectComparisonStatus.selecting) ...[
            Semantics(
              liveRegion: true,
              label: 'Đang mở thư viện ảnh',
              child: const LinearProgressIndicator(),
            ),
            const SizedBox(height: 8),
            const Text('Đang mở thư viện ảnh…'),
          ],
          if (state.status == DirectComparisonStatus.uploading) ...[
            Semantics(
              key: const Key('direct-comparison-upload-progress'),
              liveRegion: true,
              label: 'Đang tải ảnh lên để so sánh',
              value: '${(state.uploadProgress * 100).round()}%',
              child: LinearProgressIndicator(value: state.uploadProgress),
            ),
            const SizedBox(height: 8),
            Text('Đang tải ảnh lên ${(state.uploadProgress * 100).round()}%'),
          ],
          if (state.status == DirectComparisonStatus.processing) ...[
            Semantics(
              key: const Key('direct-comparison-processing'),
              liveRegion: true,
              label: 'Đang chạy hai mô hình',
              child: const LinearProgressIndicator(),
            ),
            const SizedBox(height: 8),
            const Text('Đang chạy hai mô hình'),
            const SizedBox(height: 4),
            const Text(
              'Dịch vụ AI đang lần lượt xử lý ảnh bằng Baseline và VMamba.',
            ),
          ],
          if (state.status == DirectComparisonStatus.error ||
              state.status == DirectComparisonStatus.cancelled) ...[
            Semantics(
              liveRegion: true,
              container: true,
              label: state.message ?? 'Không thể chạy so sánh',
              child: Text(
                state.message ?? 'Không thể hoàn tất quá trình phân tích.',
                key: const Key('direct-comparison-error'),
                style: TextStyle(color: context.appColors.danger),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state.image != null && bothModelsReady)
                  OutlinedButton.icon(
                    key: const Key('direct-comparison-retry'),
                    onPressed: onCompare,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                OutlinedButton.icon(
                  key: const Key('direct-comparison-error-pick-another'),
                  onPressed: onPickAnother,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh khác'),
                ),
                TextButton(
                  key: const Key('direct-comparison-reset'),
                  onPressed: onReset,
                  child: const Text('Đặt lại'),
                ),
              ],
            ),
          ],
          if (state.isBusy) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('direct-comparison-cancel'),
              onPressed: state.status == DirectComparisonStatus.selecting
                  ? null
                  : onCancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Hủy yêu cầu'),
            ),
          ] else ...[
            if (disabledReason != null) const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('direct-compare-button'),
              onPressed: canCompare ? onCompare : null,
              icon: const Icon(Icons.compare_arrows),
              label: const Text('So sánh'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComparisonResultView extends StatelessWidget {
  const _ComparisonResultView({
    required this.state,
    required this.mobilePanel,
    required this.onMobilePanelChanged,
    required this.onCompareAgain,
    required this.onPickAnother,
    required this.onReset,
  });

  final DirectComparisonState state;
  final _ComparisonPanel mobilePanel;
  final ValueChanged<_ComparisonPanel> onMobilePanelChanged;
  final VoidCallback onCompareAgain;
  final VoidCallback onPickAnother;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final image = state.image!;
    final result = state.result!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MemoryImageCard(
          title: 'Ảnh gốc',
          bytes: image.bytes,
          semanticLabel: 'Ảnh nội soi gốc dùng để so sánh',
          imageKey: const Key('direct-comparison-original-image'),
          fullscreenKey: const Key('direct-comparison-original-fullscreen'),
        ),
        const SizedBox(height: 16),
        _CommonComparisonMetadata(result: result),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final baseline = _ModelResultPanel(
              panelKey: const Key('direct-baseline-result-panel'),
              heading: 'Baseline',
              result: result.baseline,
              imageKey: const Key('direct-baseline-overlay-image'),
              fullscreenKey: const Key('direct-baseline-fullscreen'),
            );
            final vmamba = _ModelResultPanel(
              panelKey: const Key('direct-vmamba-result-panel'),
              heading: 'VMamba integration',
              result: result.vmamba,
              imageKey: const Key('direct-vmamba-overlay-image'),
              fullscreenKey: const Key('direct-vmamba-fullscreen'),
            );
            if (constraints.maxWidth >= 720) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: baseline),
                  const SizedBox(width: 12),
                  Expanded(child: vmamba),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'Chọn kết quả mô hình để xem',
                  child: SegmentedButton<_ComparisonPanel>(
                    key: const Key('direct-comparison-model-segment'),
                    segments: const [
                      ButtonSegment(
                        value: _ComparisonPanel.baseline,
                        label: Text('Baseline'),
                      ),
                      ButtonSegment(
                        value: _ComparisonPanel.vmamba,
                        label: Text('VMamba'),
                      ),
                    ],
                    selected: {mobilePanel},
                    onSelectionChanged: (selection) =>
                        onMobilePanelChanged(selection.first),
                  ),
                ),
                const SizedBox(height: 12),
                mobilePanel == _ComparisonPanel.baseline ? baseline : vmamba,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(result.warning),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('direct-comparison-again'),
                    onPressed: onCompareAgain,
                    icon: const Icon(Icons.refresh),
                    label: const Text('So sánh lại'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('direct-comparison-pick-another'),
                    onPressed: onPickAnother,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Chọn ảnh khác'),
                  ),
                  TextButton(
                    key: const Key('direct-comparison-result-reset'),
                    onPressed: onReset,
                    child: const Text('Đặt lại'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CommonComparisonMetadata extends StatelessWidget {
  const _CommonComparisonMetadata({required this.result});

  final AiComparisonResult result;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
        children: [
          _Metric(label: 'Tên tệp gốc', value: result.originalFileName),
          _Metric(
            label: 'Kích thước ảnh',
            value: '${result.originalWidth} × ${result.originalHeight} px',
          ),
          _Metric(
            label: 'Tổng thời gian xử lý',
            value: '${result.totalProcessingTimeMs.toStringAsFixed(1)} ms',
          ),
          if (kDebugMode) _Metric(label: 'Request ID', value: result.requestId),
        ],
      ),
    );
  }
}

class _ModelResultPanel extends StatelessWidget {
  const _ModelResultPanel({
    required this.panelKey,
    required this.heading,
    required this.result,
    required this.imageKey,
    required this.fullscreenKey,
  });

  final Key panelKey;
  final String heading;
  final AiComparisonModelResult result;
  final Key imageKey;
  final Key fullscreenKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: panelKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MemoryImageCard(
          title: '$heading · Overlay',
          bytes: result.overlay.bytes,
          semanticLabel: 'Ảnh overlay phân đoạn $heading',
          imageKey: imageKey,
          fullscreenKey: fullscreenKey,
        ),
        const SizedBox(height: 10),
        AppCard(
          semanticLabel: 'Thông số kết quả $heading',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(heading, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(
                result.detected
                    ? 'Đã phát hiện vùng nghi ngờ polyp.'
                    : 'Không phát hiện vùng polyp trong ảnh.',
                key: Key('direct-${result.modelKey}-detected'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 18,
                runSpacing: 14,
                children: [
                  _Metric(label: 'Mô hình', value: result.modelName),
                  _Metric(label: 'Model key', value: result.modelKey),
                  _Metric(label: 'Nhóm mô hình', value: result.modelFamily),
                  if (result.label != null)
                    _Metric(label: 'Nhãn', value: result.label!),
                  _Metric(
                    label: 'Độ tin cậy của dự đoán',
                    value: '${(result.confidence * 100).toStringAsFixed(1)}%',
                  ),
                  _Metric(
                    label: 'Số vùng phân đoạn',
                    value: '${result.maskCount}',
                  ),
                  _Metric(
                    label: 'Thời gian xử lý',
                    value: '${result.processingTimeMs.toStringAsFixed(1)} ms',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
