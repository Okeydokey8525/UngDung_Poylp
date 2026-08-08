import 'dart:typed_data';

import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/comparison/comparison_controller.dart';
import 'package:app_polyp/features/comparison/comparison_state.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ComparisonScreen extends ConsumerWidget {
  const ComparisonScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(comparisonControllerProvider);
    final controller = ref.read(comparisonControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const AppSectionHeader(
          title: 'So sánh hai mô hình',
          subtitle:
              'Ảnh sẽ được xử lý lần lượt bằng YOLO26n-seg và '
              'YOLO26n-VMamba-seg.',
        ),
        const SizedBox(height: 18),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Chọn một ảnh nội soi',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  _SelectedImagePreview(image: state.selectedImage),
                  if (state.selectedImage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.selectedImage!.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _formatBytes(state.selectedImage!.sizeBytes),
                      style: TextStyle(color: context.appColors.muted),
                    ),
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    key: const Key('comparison-pick-image'),
                    onPressed: state.isBusy ? null : controller.pickImage,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(
                      state.selectedImage == null ? 'Chọn ảnh' : 'Đổi ảnh',
                    ),
                  ),
                  if (state.message != null) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        state.message!,
                        key: const Key('comparison-error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                  if (state.status == ComparisonStatus.uploading) ...[
                    const SizedBox(height: 14),
                    Semantics(
                      label: 'Tiến trình tải ảnh so sánh',
                      value: '${(state.uploadProgress * 100).round()}%',
                      child: LinearProgressIndicator(
                        key: const Key('comparison-upload-progress'),
                        value: state.uploadProgress,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Đang tải ảnh lên ${(state.uploadProgress * 100).round()}%',
                    ),
                  ],
                  if (state.status == ComparisonStatus.processing) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(),
                    const SizedBox(height: 6),
                    const Text(
                      'Hệ thống đang chạy lần lượt Baseline và VMamba...',
                      key: Key('comparison-processing'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('compare-button'),
                    onPressed: state.canCompare
                        ? () async {
                            final result = await controller.compare();
                            if (result != null && context.mounted) {
                              context.push(
                                AppRoutes.comparisonResult(
                                  result.comparisonGroupId,
                                ),
                                extra: result,
                              );
                            }
                          }
                        : null,
                    icon: const Icon(Icons.compare_arrows),
                    label: const Text('So sánh'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const ResearchDisclaimer(key: Key('comparison-disclaimer')),
      ],
    );
  }
}

class _SelectedImagePreview extends StatelessWidget {
  const _SelectedImagePreview({required this.image});

  final SelectedDiagnosisImage? image;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: image == null,
      image: image != null,
      label: image == null
          ? 'Vùng chọn ảnh để so sánh hai mô hình'
          : 'Ảnh đã chọn để so sánh: ${image!.name}',
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
                    Icon(Icons.compare_outlined, size: 58),
                    SizedBox(height: 10),
                    Text('Chưa chọn ảnh'),
                  ],
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(AppColors.radiusNormal),
                  child: FutureBuilder<Uint8List>(
                    future: image!.readBytes(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Image.memory(
                        snapshot.data!,
                        key: const Key('comparison-image-preview'),
                        fit: BoxFit.contain,
                        semanticLabel: 'Ảnh xem trước ${image!.name}',
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
