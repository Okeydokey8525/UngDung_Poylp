import 'dart:io';

import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/comparison/comparison_models.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_api.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ComparisonRepository {
  Future<ComparisonResult> createComparison(
    SelectedDiagnosisImage image, {
    UploadProgressCallback? onSendProgress,
  });

  Future<ComparisonResult> getComparison(String comparisonGroupId);

  Future<void> deleteComparison(String comparisonGroupId);
}

class ComparisonApi implements ComparisonRepository {
  const ComparisonApi(this._client, this._csrf);

  final ApiClient _client;
  final CsrfController _csrf;

  @override
  Future<ComparisonResult> createComparison(
    SelectedDiagnosisImage image, {
    UploadProgressCallback? onSendProgress,
  }) async {
    await _csrf.ensure();
    final multipart = await _multipartFile(image);
    final json = await _client.postMultipart(
      '/api/v1/comparisons',
      data: FormData.fromMap({'image': multipart}),
      onSendProgress: onSendProgress,
      timeout: const Duration(seconds: 240),
    );
    return _parse(json);
  }

  @override
  Future<ComparisonResult> getComparison(String comparisonGroupId) async {
    final json = await _client.getJson(
      '/api/v1/comparisons/$comparisonGroupId',
    );
    return _parse(json);
  }

  @override
  Future<void> deleteComparison(String comparisonGroupId) async {
    await _csrf.ensure();
    await _client.deleteNoContent('/api/v1/comparisons/$comparisonGroupId');
  }

  ComparisonResult _parse(Map<String, dynamic> json) {
    try {
      final result = ComparisonResult.fromJson(json);
      if (result.comparisonGroupId.isEmpty ||
          result.originalImageUrl.isEmpty ||
          result.baseline.id.isEmpty ||
          result.baseline.resultImageUrl.isEmpty ||
          result.vmamba.id.isEmpty ||
          result.vmamba.resultImageUrl.isEmpty) {
        throw const FormatException('Invalid comparison response');
      }
      return result;
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phiên so sánh không hợp lệ.',
      );
    }
  }

  Future<MultipartFile> _multipartFile(SelectedDiagnosisImage image) async {
    final type = DioMediaType.parse(image.mimeType);
    final safeName = image.name
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[\r\n"]'), '');
    if (image.file.path.isNotEmpty && File(image.file.path).existsSync()) {
      return MultipartFile.fromFile(
        image.file.path,
        filename: safeName,
        contentType: type,
      );
    }
    return MultipartFile.fromBytes(
      await image.readBytes(),
      filename: safeName.isEmpty ? 'image.jpg' : safeName,
      contentType: type,
    );
  }
}

final comparisonApiProvider = Provider<ComparisonRepository>(
  (ref) => ComparisonApi(
    ref.watch(apiClientProvider),
    ref.watch(csrfControllerProvider),
  ),
);
