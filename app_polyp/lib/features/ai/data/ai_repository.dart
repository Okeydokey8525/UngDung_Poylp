import 'dart:typed_data';

import 'package:app_polyp/core/network/ai_api_exception.dart';
import 'package:app_polyp/core/network/ai_error_mapper.dart';
import 'package:app_polyp/core/network/direct_ai_client.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

typedef AiUploadProgress = void Function(int sent, int total);

final class AiImageUpload {
  const AiImageUpload({
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.readBytes,
  });

  factory AiImageUpload.fromXFile(
    XFile file, {
    required String mimeType,
    required int sizeBytes,
  }) => AiImageUpload(
    name: file.name,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    readBytes: file.readAsBytes,
  );

  final String name;
  final String mimeType;
  final int sizeBytes;
  final Future<Uint8List> Function() readBytes;
}

abstract interface class AiRepository {
  Future<AiHealthResponse> getHealth();

  Future<AiModelsResponse> getModels();

  Future<AiInferenceResult> infer({
    required AiImageUpload image,
    required String modelKey,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  });

  Future<AiComparisonResult> compare({
    required AiImageUpload image,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  });
}

final class DirectAiRepository implements AiRepository {
  const DirectAiRepository(this._client);

  final DirectAiClient _client;

  @override
  Future<AiHealthResponse> getHealth() async {
    final json = await _client.getJson(
      '/api/v1/health',
      acceptedStatusCodes: const {503},
    );
    return _parse(() => AiHealthResponse.fromJson(json));
  }

  @override
  Future<AiModelsResponse> getModels() async {
    final json = await _client.getJson('/api/v1/models');
    return _parse(() => AiModelsResponse.fromJson(json));
  }

  @override
  Future<AiInferenceResult> infer({
    required AiImageUpload image,
    required String modelKey,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      'image': await _multipartFile(image),
      'modelKey': modelKey,
    });
    final json = await _client.postMultipart(
      '/api/v1/inference',
      data: formData,
      sendTimeout: DirectAiClient.inferenceSendTimeout,
      receiveTimeout: DirectAiClient.inferenceReceiveTimeout,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    return _parse(() => AiInferenceResult.fromJson(json));
  }

  @override
  Future<AiComparisonResult> compare({
    required AiImageUpload image,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({'image': await _multipartFile(image)});
    final json = await _client.postMultipart(
      '/api/v1/comparison',
      data: formData,
      sendTimeout: DirectAiClient.comparisonSendTimeout,
      receiveTimeout: DirectAiClient.comparisonReceiveTimeout,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    return _parse(() => AiComparisonResult.fromJson(json));
  }

  T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on AiApiException {
      rethrow;
    } on FormatException {
      throw AiErrorMapper.invalidResponse();
    } on TypeError {
      throw AiErrorMapper.invalidResponse();
    }
  }

  Future<MultipartFile> _multipartFile(AiImageUpload image) async =>
      MultipartFile.fromBytes(
        await image.readBytes(),
        filename: _safeFileName(image.name),
        contentType: DioMediaType.parse(image.mimeType),
      );

  String _safeFileName(String value) {
    final normalized = value.replaceAll('\\', '/');
    final name = normalized.split('/').last.replaceAll(RegExp(r'[\r\n"]'), '');
    return name.isEmpty ? 'image.jpg' : name;
  }
}
