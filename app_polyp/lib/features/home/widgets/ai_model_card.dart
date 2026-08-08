import 'package:app_polyp/app/app_colors.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_status_badge.dart';
import 'package:flutter/material.dart';

class AiModelCard extends StatelessWidget {
  const AiModelCard({required this.model, super.key, this.compact = false});

  final AiModelInfo model;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final familyLabel = switch (model.family.toLowerCase()) {
      'baseline' => 'Baseline',
      'vmamba' => 'VMamba integration',
      _ => model.family,
    };
    final description = switch (model.key) {
      'YOLO26n-seg' => 'Mô hình baseline dùng để đối chiếu.',
      'YOLO26n-VMamba-seg' =>
        'Mô hình nghiên cứu tích hợp khối VMamba vào backbone.',
      _ => 'Mô hình phân đoạn phục vụ nghiên cứu.',
    };
    return AppCard(
      semanticLabel:
          '${model.name}, $familyLabel, ${model.ready ? 'sẵn sàng' : 'chưa sẵn sàng'}',
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  model.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(width: 8),
              AppStatusBadge(
                status: model.ready ? AppStatus.clear : AppStatus.warning,
                text: model.ready ? 'Sẵn sàng' : 'Chưa sẵn sàng',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(model.key, style: TextStyle(color: context.appColors.muted)),
          const SizedBox(height: 10),
          Text(
            familyLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(description),
        ],
      ),
    );
  }
}
