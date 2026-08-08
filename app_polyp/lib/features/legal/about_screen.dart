import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/research_disclaimer.dart';
import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giới thiệu')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'PolypVision',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Giao diện nghiên cứu phương pháp tích hợp VMamba vào '
              'YOLO26-seg trong phân đoạn polyp từ ảnh nội soi đại trực tràng.',
            ),
            const SizedBox(height: 18),
            const AppCard(
              child: Text(
                'M1 xây dựng foundation Flutter, design system và luồng mock. '
                'Nội dung đầy đủ sẽ được đồng bộ từ backend ở M2/M3.',
              ),
            ),
            const SizedBox(height: 18),
            const ResearchDisclaimer(),
          ],
        ),
      ),
    );
  }
}
