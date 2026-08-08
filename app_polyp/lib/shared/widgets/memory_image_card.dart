import 'dart:typed_data';

import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/fullscreen_memory_image.dart';
import 'package:flutter/material.dart';

class MemoryImageCard extends StatelessWidget {
  const MemoryImageCard({
    required this.title,
    required this.bytes,
    required this.semanticLabel,
    required this.imageKey,
    required this.fullscreenKey,
    super.key,
  });

  final String title;
  final Uint8List bytes;
  final String semanticLabel;
  final Key imageKey;
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
            child: Image.memory(
              bytes,
              key: imageKey,
              fit: BoxFit.contain,
              semanticLabel: semanticLabel,
              gaplessPlayback: true,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            key: fullscreenKey,
            onPressed: () => FullscreenMemoryImage.show(
              context,
              FullscreenMemoryImageArguments(
                bytes: bytes,
                title: title,
                semanticLabel: semanticLabel,
              ),
            ),
            icon: const Icon(Icons.fullscreen),
            label: const Text('Xem toàn màn hình'),
          ),
        ],
      ),
    );
  }
}
