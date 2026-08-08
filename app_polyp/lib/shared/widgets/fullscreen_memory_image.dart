import 'dart:typed_data';

import 'package:flutter/material.dart';

final class FullscreenMemoryImageArguments {
  const FullscreenMemoryImageArguments({
    required this.bytes,
    required this.title,
    required this.semanticLabel,
  });

  final Uint8List bytes;
  final String title;
  final String semanticLabel;
}

class FullscreenMemoryImage extends StatelessWidget {
  const FullscreenMemoryImage({required this.arguments, super.key});

  final FullscreenMemoryImageArguments arguments;

  static Future<void> show(
    BuildContext context,
    FullscreenMemoryImageArguments arguments,
  ) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => FullscreenMemoryImage(arguments: arguments),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('fullscreen-memory-image'),
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(arguments.title),
        leading: IconButton(
          key: const Key('fullscreen-memory-close'),
          tooltip: 'Đóng ảnh toàn màn hình',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: Semantics(
          image: true,
          label: '${arguments.semanticLabel} toàn màn hình',
          child: InteractiveViewer(
            key: const Key('fullscreen-memory-interactive-viewer'),
            minScale: 0.8,
            maxScale: 5,
            child: SizedBox.expand(
              child: Image.memory(
                arguments.bytes,
                fit: BoxFit.contain,
                semanticLabel: '${arguments.semanticLabel} toàn màn hình',
                excludeFromSemantics: true,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
