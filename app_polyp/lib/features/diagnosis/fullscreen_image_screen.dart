import 'package:app_polyp/features/diagnosis/authenticated_image.dart';
import 'package:flutter/material.dart';

class AuthenticatedImageArguments {
  const AuthenticatedImageArguments({required this.url, required this.title});

  final String url;
  final String title;
}

class FullscreenImageScreen extends StatelessWidget {
  const FullscreenImageScreen({required this.arguments, super.key});

  final AuthenticatedImageArguments arguments;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(arguments.title),
        leading: IconButton(
          tooltip: 'Đóng ảnh toàn màn hình',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ),
      body: SafeArea(
        child: InteractiveViewer(
          key: const Key('fullscreen-interactive-viewer'),
          minScale: 0.8,
          maxScale: 5,
          child: SizedBox.expand(
            child: AuthenticatedImage(
              url: arguments.url,
              semanticLabel: '${arguments.title} toàn màn hình',
            ),
          ),
        ),
      ),
    );
  }
}
