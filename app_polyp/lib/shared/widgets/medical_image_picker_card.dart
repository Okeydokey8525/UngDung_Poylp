import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/shared/medical_image/medical_image.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';

class MedicalImagePickerCard extends StatelessWidget {
  const MedicalImagePickerCard({
    required this.image,
    required this.onPick,
    required this.onRemove,
    required this.pickButtonKey,
    required this.removeButtonKey,
    required this.previewKey,
    required this.fileNameKey,
    super.key,
    this.title = '1. Chọn ảnh',
    this.emptyMessage = 'Chưa chọn ảnh',
  });

  final SelectedMedicalImage? image;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;
  final Key pickButtonKey;
  final Key removeButtonKey;
  final Key previewKey;
  final Key fileNameKey;
  final String title;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final selected = image;
    return AppCard(
      semanticLabel: selected == null
          ? 'Khu vực chọn ảnh nội soi'
          : 'Ảnh nội soi đã chọn: ${selected.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.appColors.surfaceAlt,
                borderRadius: BorderRadius.circular(AppColors.radiusNormal),
                border: Border.all(color: context.appColors.border),
              ),
              child: selected == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 52,
                          semanticLabel: 'Chưa chọn ảnh nội soi',
                        ),
                        const SizedBox(height: 10),
                        Text(emptyMessage),
                        const SizedBox(height: 4),
                        const Text('JPG, JPEG hoặc PNG · tối đa 10 MB'),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppColors.radiusNormal,
                      ),
                      child: Image.memory(
                        selected.bytes,
                        key: previewKey,
                        fit: BoxFit.contain,
                        semanticLabel: 'Ảnh xem trước ${selected.name}',
                        gaplessPlayback: true,
                      ),
                    ),
            ),
          ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            Text(
              selected.name,
              key: fileNameKey,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${formatMedicalImageBytes(selected.sizeBytes)} · '
              '${selected.width} × ${selected.height} px',
              style: TextStyle(color: context.appColors.muted),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: pickButtonKey,
                onPressed: onPick,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(selected == null ? 'Chọn ảnh' : 'Chọn lại'),
              ),
              if (selected != null)
                TextButton.icon(
                  key: removeButtonKey,
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Xóa ảnh'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String formatMedicalImageBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
