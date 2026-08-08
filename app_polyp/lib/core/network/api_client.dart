import 'dart:typed_data';

import 'package:app_polyp/core/network/api_exception.dart';
import 'package:dio/dio.dart';

class ApiClient {
  const ApiClient(this.dio);

  static const _imageAccept = 'image/*, application/json';

  final Dio dio;

  String get baseUrl => dio.options.baseUrl;

  Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final response = await dio.get<dynamic>(path);
      return _jsonObject(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> postJson(String path, {Object? data}) async {
    try {
      final response = await dio.post<dynamic>(path, data: data);
      return _jsonObject(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required FormData data,
    ProgressCallback? onSendProgress,
    Duration? timeout,
  }) async {
    try {
      final response = await dio.post<dynamic>(
        path,
        data: data,
        onSendProgress: onSendProgress,
        options: Options(sendTimeout: timeout, receiveTimeout: timeout),
      );
      return _jsonObject(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Uint8List> getBytes(String path) async {
    try {
      final response = await dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {Headers.acceptHeader: _imageAccept},
        ),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const ApiException(
          code: 'INVALID_RESPONSE',
          message: 'Máy chủ không trả về dữ liệu ảnh.',
        );
      }
      final contentType = _normalizedContentType(response);
      if (contentType == 'application/json') {
        throw ApiException.fromResponse(response);
      }
      if (contentType != 'image/jpeg' && contentType != 'image/png') {
        throw const ApiException(
          code: 'INVALID_RESPONSE',
          message: 'Máy chủ trả về phản hồi không hợp lệ.',
        );
      }
      if (!_hasValidImageSignature(data, contentType)) {
        throw const ApiException(
          code: 'INVALID_RESPONSE',
          message: 'Dữ liệu ảnh từ máy chủ không hợp lệ.',
        );
      }
      return Uint8List.fromList(data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> deleteNoContent(String path) async {
    try {
      await dio.delete<void>(path);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<Map<String, dynamic>> patchJson(String path, {Object? data}) async {
    try {
      final response = await dio.patch<dynamic>(path, data: data);
      return _jsonObject(response);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> putNoContent(String path, {Object? data}) async {
    try {
      await dio.put<void>(path, data: data);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> postNoContent(String path) async {
    try {
      await dio.post<void>(path);
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Map<String, dynamic> _jsonObject(Response<dynamic> response) {
    final contentType = response.headers.value(Headers.contentTypeHeader);
    if (!(contentType?.toLowerCase().contains('application/json') ?? false) ||
        response.data is! Map) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  String _normalizedContentType(Response<dynamic> response) =>
      response.headers
          .value(Headers.contentTypeHeader)
          ?.split(';')
          .first
          .trim()
          .toLowerCase() ??
      '';

  bool _hasValidImageSignature(List<int> data, String contentType) {
    if (contentType == 'image/jpeg') {
      return data.length >= 3 &&
          data[0] == 0xff &&
          data[1] == 0xd8 &&
          data[2] == 0xff;
    }
    const pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    return data.length >= pngSignature.length &&
        List.generate(
          pngSignature.length,
          (index) => data[index] == pngSignature[index],
        ).every((matches) => matches);
  }
}
