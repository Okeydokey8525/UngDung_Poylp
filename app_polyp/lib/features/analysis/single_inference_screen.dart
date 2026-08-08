import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/analysis/direct_analysis_controller.dart';
import 'package:app_polyp/features/analysis/direct_analysis_state.dart';
import 'package:app_polyp/features/home/widgets/ai_model_card.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:app_polyp/shared/widgets/medical_image_picker_card.dart';
import 'package:app_polyp/shared/widgets/memory_image_card.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DirectAnalysisScreen extends ConsumerStatefulWidget {
  const DirectAnalysisScreen({super.key});

  @override
  ConsumerState<DirectAnalysisScreen> createState() =>
      _DirectAnalysisScreenState();
}

class _DirectAnalysisScreenState extends ConsumerState<DirectAnalysisScreen> {
  String? _lastSynchronizedModelsRequestId;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(directAnalysisControllerProvider);
    final controller = ref.read(directAnalysisControllerProvider.notifier);
    final models = ref.watch(aiModelsProvider);
    models.whenData((value) {
      if (_lastSynchronizedModelsRequestId == value.requestId) return;
      _lastSynchronizedModelsRequestId = value.requestId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.synchronizeModels(value.models);
      });
    });
    final readyModelKeys =
        models.asData?.value.models
            .where((model) => model.ready)
            .map((model) => model.key)
            .toSet() ??
        const <String>{};

    return ListView(
      key: const Key('direct-analysis-screen'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        AppSectionHeader(
          title: state.hasResult
              ? 'Kết quả phân đoạn'
              : 'Phân tích ảnh nội soi',
          subtitle: state.hasResult
              ? state.image?.name ?? 'Ảnh nội soi'
              : 'Chọn ảnh nội soi và một mô hình sẵn sàng để phân đoạn.',
        ),
        const SizedBox(height: 18),
        if (state.hasResult)
          _InferenceResultView(
            state: state,
            readyModelKeys: readyModelKeys,
            onAnalyzeAgain: () =>
                controller.analyze(readyModelKeys: readyModelKeys),
            onPickAnother: controller.pickImage,
            onReset: controller.reset,
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final imageCard = MedicalImagePickerCard(
                image: state.image,
                onPick: state.isBusy ? null : controller.pickImage,
                onRemove: state.isBusy || state.image == null
                    ? null
                    : controller.removeImage,
                pickButtonKey: const Key('direct-analysis-pick-image'),
                removeButtonKey: const Key('direct-analysis-remove-image'),
                previewKey: const Key('direct-selected-image-preview'),
                fileNameKey: const Key('direct-selected-image-name'),
              );
              final modelSelector = _ModelSelector(
                models: models,
                selectedModelKey: state.selectedModelKey,
                busy: state.isBusy,
                onSelected: (key) =>
                    controller.selectModel(key, readyModelKeys: readyModelKeys),
                onRetry: () => ref.invalidate(aiModelsProvider),
              );
              if (constraints.maxWidth < 760) {
                return Column(
                  children: [
                    imageCard,
                    const SizedBox(height: 16),
                    modelSelector,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: imageCard),
                  const SizedBox(width: 16),
                  Expanded(child: modelSelector),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _InferenceControls(
            state: state,
            modelReady:
                state.selectedModelKey != null &&
                readyModelKeys.contains(state.selectedModelKey),
            onAnalyze: () => controller.analyze(readyModelKeys: readyModelKeys),
            onCancel: controller.cancel,
            onPickAnother: controller.pickImage,
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
        const ResearchDisclaimer(key: Key('direct-analysis-disclaimer')),
      ],
    );
  }
}

class _ModelSelector extends StatelessWidget {
  const _ModelSelector({
    required this.models,
    required this.selectedModelKey,
    required this.busy,
    required this.onSelected,
    required this.onRetry,
  });

  final AsyncValue<AiModelsResponse> models;
  final String? selectedModelKey;
  final bool busy;
  final ValueChanged<String> onSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      semanticLabel: 'Chọn mô hình phân đoạn',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '2. Chọn mô hình',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          models.when(
            loading: () => Semantics(
              liveRegion: true,
              label: 'Đang tải danh sách mô hình',
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('Đang tải mô hình…')),
                ],
              ),
            ),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Không thể tải danh sách mô hình.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const Key('analysis-models-retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
            data: (value) {
              final hasReadyModel = value.models.any((model) => model.ready);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hasReadyModel) ...[
                    const Text(
                      'Hiện không có mô hình nào sẵn sàng.',
                      key: Key('direct-analysis-no-ready-model'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const Key('analysis-models-retry'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Thử lại'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final model in value.models)
                        ChoiceChip(
                          key: Key('analysis-model-${model.key}'),
                          label: Text(model.name),
                          selected: selectedModelKey == model.key,
                          onSelected: model.ready && !busy
                              ? (selected) {
                                  if (selected) onSelected(model.key);
                                }
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
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

class _InferenceControls extends StatelessWidget {
  const _InferenceControls({
    required this.state,
    required this.modelReady,
    required this.onAnalyze,
    required this.onCancel,
    required this.onPickAnother,
    required this.onReset,
  });

  final DirectAnalysisState state;
  final bool modelReady;
  final VoidCallback onAnalyze;
  final VoidCallback onCancel;
  final VoidCallback onPickAnother;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final canAnalyze = state.image != null && modelReady && !state.isBusy;
    final disabledReason = state.image == null
        ? 'Hãy chọn một ảnh hợp lệ trước khi phân tích.'
        : !modelReady
        ? 'Hãy chọn một mô hình đang sẵn sàng.'
        : null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (disabledReason != null && !state.isBusy)
            Text(disabledReason, key: const Key('analysis-disabled-reason')),
          if (state.status == DirectAnalysisStatus.selecting) ...[
            Semantics(
              liveRegion: true,
              label: 'Đang mở thư viện ảnh',
              child: LinearProgressIndicator(),
            ),
            const SizedBox(height: 8),
            const Text('Đang mở thư viện ảnh…'),
          ],
          if (state.status == DirectAnalysisStatus.uploading) ...[
            Semantics(
              key: const Key('direct-inference-upload-progress'),
              liveRegion: true,
              label: 'Đang tải ảnh lên',
              value: '${(state.uploadProgress * 100).round()}%',
              child: LinearProgressIndicator(value: state.uploadProgress),
            ),
            const SizedBox(height: 8),
            Text('Đang tải ảnh lên ${(state.uploadProgress * 100).round()}%'),
          ],
          if (state.status == DirectAnalysisStatus.processing) ...[
            Semantics(
              liveRegion: true,
              label: 'Đang phân tích bằng mô hình AI',
              child: LinearProgressIndicator(
                key: Key('direct-inference-processing'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Đang phân tích bằng mô hình AI…'),
          ],
          if (state.status == DirectAnalysisStatus.error ||
              state.status == DirectAnalysisStatus.cancelled) ...[
            Semantics(
              liveRegion: true,
              container: true,
              label: state.message ?? 'Không thể phân tích ảnh',
              child: Text(
                state.message ?? 'Không thể hoàn tất quá trình phân tích.',
                key: const Key('direct-analysis-error'),
                style: TextStyle(color: context.appColors.danger),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (state.image != null && modelReady)
                  OutlinedButton.icon(
                    key: const Key('direct-analysis-retry'),
                    onPressed: onAnalyze,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                OutlinedButton.icon(
                  key: const Key('direct-analysis-error-pick-another'),
                  onPressed: onPickAnother,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Chọn ảnh khác'),
                ),
                TextButton(
                  key: const Key('direct-analysis-reset'),
                  onPressed: onReset,
                  child: const Text('Đặt lại'),
                ),
              ],
            ),
          ],
          if (state.isBusy) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('direct-analysis-cancel'),
              onPressed: state.status == DirectAnalysisStatus.selecting
                  ? null
                  : onCancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Hủy yêu cầu'),
            ),
          ] else ...[
            if (disabledReason != null) const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('direct-analyze-button'),
              onPressed: canAnalyze ? onAnalyze : null,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Phân tích'),
            ),
          ],
        ],
      ),
    );
  }
}

class _InferenceResultView extends StatelessWidget {
  const _InferenceResultView({
    required this.state,
    required this.readyModelKeys,
    required this.onAnalyzeAgain,
    required this.onPickAnother,
    required this.onReset,
  });

  final DirectAnalysisState state;
  final Set<String> readyModelKeys;
  final VoidCallback onAnalyzeAgain;
  final VoidCallback onPickAnother;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final image = state.image!;
    final result = state.result!;
    final modelStillReady = readyModelKeys.contains(result.modelKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          semanticLabel: result.detected
              ? 'Đã phát hiện vùng nghi ngờ polyp'
              : 'Không phát hiện vùng polyp trong ảnh',
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                result.detected
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                color: result.detected
                    ? context.appColors.warning
                    : context.appColors.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  result.detected
                      ? 'Đã phát hiện vùng nghi ngờ polyp'
                      : 'Không phát hiện vùng polyp trong ảnh',
                  key: const Key('direct-inference-detection-status'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final original = MemoryImageCard(
              title: 'Ảnh gốc',
              bytes: image.bytes,
              semanticLabel: 'Ảnh nội soi gốc',
              imageKey: const Key('direct-result-original-image'),
              fullscreenKey: const Key('direct-original-fullscreen'),
            );
            final overlay = MemoryImageCard(
              title: 'Overlay phân đoạn',
              bytes: result.overlay.bytes,
              semanticLabel: 'Ảnh overlay phân đoạn',
              imageKey: const Key('direct-result-overlay-image'),
              fullscreenKey: const Key('direct-overlay-fullscreen'),
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
        const SizedBox(height: 16),
        _InferenceMetadataCard(result: result),
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
                    key: const Key('direct-analysis-again'),
                    onPressed: modelStillReady ? onAnalyzeAgain : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Phân tích lại'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('direct-analysis-pick-another'),
                    onPressed: onPickAnother,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Chọn ảnh khác'),
                  ),
                  TextButton(
                    key: const Key('direct-analysis-result-reset'),
                    onPressed: onReset,
                    child: const Text('Đặt lại'),
                  ),
                ],
              ),
              if (!modelStillReady) ...[
                const SizedBox(height: 10),
                const Text(
                  'Mô hình của kết quả này hiện chưa sẵn sàng để phân tích lại.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InferenceMetadataCard extends StatelessWidget {
  const _InferenceMetadataCard({required this.result});

  final AiInferenceResult result;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Wrap(
        spacing: 24,
        runSpacing: 16,
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
          _Metric(label: 'Số vùng mask', value: '${result.maskCount}'),
          _Metric(
            label: 'Thời gian xử lý',
            value: '${result.processingTimeMs.toStringAsFixed(1)} ms',
          ),
          _Metric(
            label: 'Kích thước ảnh',
            value: '${result.originalWidth} × ${result.originalHeight} px',
          ),
          _Metric(label: 'Tên tệp gốc', value: result.originalFileName),
          if (kDebugMode) _Metric(label: 'Request ID', value: result.requestId),
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
      width: 210,
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
