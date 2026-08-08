import 'dart:io';
import 'dart:typed_data';

import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef UploadProgressCallback = void Function(int sent, int total);

abstract interface class DiagnosisRepository {
  Future<DiagnosisResult> createDiagnosis(
    SelectedDiagnosisImage image,
    DiagnosisModelOption model, {
    UploadProgressCallback? onSendProgress,
  });

  Future<DiagnosisResult> getDiagnosis(String id);

  Future<Uint8List> loadImage(String url);

  Future<void> deleteDiagnosis(String id);
}

class DiagnosisApi implements DiagnosisRepository {
  const DiagnosisApi(this._client, this._csrf);

  final ApiClient _client;
  final CsrfController _csrf;

  @override
  Future<DiagnosisResult> createDiagnosis(
    SelectedDiagnosisImage image,
    DiagnosisModelOption model, {
    UploadProgressCallback? onSendProgress,
  }) async {
    await _csrf.ensure();
    final multipart = await _multipartFile(image);
    final formData = FormData.fromMap({
      'image': multipart,
      'modelType': model.apiValue,
    });
    final json = await _client.postMultipart(
      '/api/v1/diagnoses',
      data: formData,
      onSendProgress: onSendProgress,
      timeout: const Duration(seconds: 120),
    );
    return _parseResult(json);
  }

  @override
  Future<DiagnosisResult> getDiagnosis(String id) async {
    final json = await _client.getJson('/api/v1/diagnoses/$id');
    return _parseResult(json);
  }

  @override
  Future<Uint8List> loadImage(String url) => _client.getBytes(url);

  @override
  Future<void> deleteDiagnosis(String id) async {
    await _csrf.ensure();
    await _client.deleteNoContent('/api/v1/diagnoses/$id');
  }

  DiagnosisResult _parseResult(Map<String, dynamic> json) {
    try {
      final result = DiagnosisResult.fromJson(json);
      if (result.id.isEmpty ||
          result.originalImageUrl.isEmpty ||
          result.resultImageUrl.isEmpty) {
        throw const FormatException('Invalid diagnosis response');
      }
      return result;
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về kết quả phân tích không hợp lệ.',
      );
    }
  }

  Future<MultipartFile> _multipartFile(SelectedDiagnosisImage image) async {
    final contentType = DioMediaType.parse(image.mimeType);
    if (image.file.path.isNotEmpty && File(image.file.path).existsSync()) {
      return MultipartFile.fromFile(
        image.file.path,
        filename: _safeFileName(image.name),
        contentType: contentType,
      );
    }
    return MultipartFile.fromBytes(
      await image.readBytes(),
      filename: _safeFileName(image.name),
      contentType: contentType,
    );
  }

  String _safeFileName(String value) {
    final normalized = value.replaceAll('\\', '/');
    final name = normalized.split('/').last.replaceAll(RegExp(r'[\r\n"]'), '');
    return name.isEmpty ? 'image.jpg' : name;
  }
}

final diagnosisApiProvider = Provider<DiagnosisRepository>(
  (ref) => DiagnosisApi(
    ref.watch(apiClientProvider),
    ref.watch(csrfControllerProvider),
  ),
);
