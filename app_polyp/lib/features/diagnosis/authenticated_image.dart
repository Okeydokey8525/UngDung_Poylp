import 'dart:typed_data';

import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthenticatedImage extends ConsumerStatefulWidget {
  const AuthenticatedImage({
    required this.url,
    required this.semanticLabel,
    super.key,
    this.fit = BoxFit.contain,
  });

  final String url;
  final String semanticLabel;
  final BoxFit fit;

  @override
  ConsumerState<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends ConsumerState<AuthenticatedImage> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _future = _load();
  }

  Future<Uint8List> _load() async {
    try {
      return await ref.read(diagnosisApiProvider).loadImage(widget.url);
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await ref
            .read(authControllerProvider.notifier)
            .clearSessionAfterSensitiveChange(
              message: 'Phiên đăng nhập đã hết hạn.',
            );
      }
      rethrow;
    }
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || snapshot.data == null) {
          final message = snapshot.error is ApiException
              ? (snapshot.error! as ApiException).message
              : 'Không thể tải ảnh.';
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, size: 42),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    key: const Key('authenticated-image-retry'),
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          gaplessPlayback: true,
          semanticLabel: widget.semanticLabel,
          excludeFromSemantics: false,
        );
      },
    );
  }
}
