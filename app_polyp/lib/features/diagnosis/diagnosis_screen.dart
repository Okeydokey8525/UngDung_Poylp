import 'dart:typed_data';

import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_state.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DiagnosisScreen extends ConsumerWidget {
  const DiagnosisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(diagnosisControllerProvider);
    final controller = ref.read(diagnosisControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const AppSectionHeader(
          title: 'Phân tích ảnh',
          subtitle: 'Chọn ảnh nội soi và mô hình phân đoạn để phân tích.',
        ),
        const SizedBox(height: 18),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final image = _ImageSelectionCard(
                  state: state,
                  onPick: state.isBusy ? null : controller.pickImage,
                );
                final controls = _AnalysisControls(
                  state: state,
                  onModelChanged: controller.selectModel,
                  onAnalyze: () async {
                    final result = await controller.analyze();
                    if (result != null && context.mounted) {
                      context.push(
                        AppRoutes.diagnosisResult(result.id),
                        extra: result,
                      );
                    }
                  },
                );
                if (!wide) {
                  return Column(
                    children: [image, const SizedBox(height: 12), controls],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: image),
                    const SizedBox(width: 12),
                    Expanded(child: controls),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 18),
        const ResearchDisclaimer(key: Key('diagnosis-disclaimer')),
      ],
    );
  }
}

class _ImageSelectionCard extends StatelessWidget {
  const _ImageSelectionCard({required this.state, required this.onPick});

  final DiagnosisState state;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final image = state.selectedImage;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '1. Chọn ảnh nội soi',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 14),
          Semantics(
            button: image == null,
            image: image != null,
            label: image == null
                ? 'Vùng chọn ảnh nội soi từ thư viện'
                : 'Ảnh nội soi đã chọn: ${image.name}',
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: context.appColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppColors.radiusNormal),
                  border: Border.all(color: context.appColors.border),
                ),
                child: image == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 52),
                          SizedBox(height: 10),
                          Text('Chưa chọn ảnh'),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(
                          AppColors.radiusNormal,
                        ),
                        child: FutureBuilder<Uint8List>(
                          future: image.readBytes(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            return Image.memory(
                              snapshot.data!,
                              key: const Key('selected-image-preview'),
                              fit: BoxFit.contain,
                              semanticLabel: 'Ảnh xem trước ${image.name}',
                            );
                          },
                        ),
                      ),
              ),
            ),
          ),
          if (image != null) ...[
            const SizedBox(height: 12),
            Text(image.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(
              _formatBytes(image.sizeBytes),
              style: TextStyle(color: context.appColors.muted),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('pick-image-button'),
            onPressed: onPick,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(image == null ? 'Chọn ảnh' : 'Đổi ảnh'),
          ),
        ],
      ),
    );
  }
}

class _AnalysisControls extends StatelessWidget {
  const _AnalysisControls({
    required this.state,
    required this.onModelChanged,
    required this.onAnalyze,
  });

  final DiagnosisState state;
  final ValueChanged<DiagnosisModelOption> onModelChanged;
  final Future<void> Function() onAnalyze;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '2. Chọn mô hình',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          RadioGroup<DiagnosisModelOption>(
            groupValue: state.selectedModel,
            onChanged: (value) {
              if (!state.isBusy && value != null) onModelChanged(value);
            },
            child: Column(
              children: [
                for (final model in DiagnosisModelOption.values)
                  RadioListTile<DiagnosisModelOption>(
                    key: Key('model-${model.name}'),
                    value: model,
                    enabled: !state.isBusy,
                    contentPadding: EdgeInsets.zero,
                    title: Text(model.apiValue),
                    subtitle: Text('${model.category} — ${model.description}'),
                  ),
              ],
            ),
          ),
          if (state.message != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                state.message!,
                key: const Key('diagnosis-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          if (state.status == DiagnosisStatus.uploading) ...[
            const SizedBox(height: 12),
            Semantics(
              label: 'Tiến trình tải ảnh lên',
              value: '${(state.uploadProgress * 100).round()}%',
              child: LinearProgressIndicator(
                key: const Key('diagnosis-upload-progress'),
                value: state.uploadProgress,
              ),
            ),
            const SizedBox(height: 6),
            Text('Đang tải ảnh lên ${(state.uploadProgress * 100).round()}%'),
          ],
          if (state.status == DiagnosisStatus.processing) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 6),
            const Text(
              'Mô hình đang xử lý ảnh...',
              key: Key('diagnosis-processing'),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('analyze-button'),
            onPressed: state.canAnalyze ? onAnalyze : null,
            icon: const Icon(Icons.science_outlined),
            label: const Text('Phân tích'),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
