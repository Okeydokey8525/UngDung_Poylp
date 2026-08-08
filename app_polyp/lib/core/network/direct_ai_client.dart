import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'ai_error_mapper.dart';
import 'ai_request_id.dart';

final class DirectAiClient {
  DirectAiClient(this.dio, this.requestIds);

  static const Duration shortRequestTimeout = Duration(seconds: 15);
  static const Duration inferenceSendTimeout = Duration(seconds: 120);
  static const Duration inferenceReceiveTimeout = Duration(seconds: 150);
  static const Duration comparisonSendTimeout = Duration(seconds: 240);
  static const Duration comparisonReceiveTimeout = Duration(seconds: 300);

  final Dio dio;
  final AiRequestIdGenerator requestIds;

  String get baseUrl => dio.options.baseUrl;

  Future<Map<String, Object?>> getJson(
    String path, {
    Set<int> acceptedStatusCodes = const {},
  }) async {
    try {
      final response = await dio.get<Object?>(
        path,
        options: _options(
          sendTimeout: shortRequestTimeout,
          receiveTimeout: shortRequestTimeout,
          acceptedStatusCodes: acceptedStatusCodes,
        ),
      );
      return _jsonObject(response.data);
    } on DioException catch (exception) {
      throw AiErrorMapper.fromDio(exception);
    } on FormatException {
      throw AiErrorMapper.invalidResponse();
    } on TypeError {
      throw AiErrorMapper.invalidResponse();
    }
  }

  Future<Map<String, Object?>> postMultipart(
    String path, {
    required FormData data,
    required Duration sendTimeout,
    required Duration receiveTimeout,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await dio.post<Object?>(
        path,
        data: data,
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
        options: _options(
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
        ),
      );
      return _jsonObject(response.data);
    } on DioException catch (exception) {
      throw AiErrorMapper.fromDio(exception);
    } on FormatException {
      throw AiErrorMapper.invalidResponse();
    } on TypeError {
      throw AiErrorMapper.invalidResponse();
    }
  }

  Options _options({
    required Duration sendTimeout,
    required Duration receiveTimeout,
    Set<int> acceptedStatusCodes = const {},
  }) => Options(
    sendTimeout: sendTimeout,
    receiveTimeout: receiveTimeout,
    headers: {
      Headers.acceptHeader: 'application/json',
      'X-Request-ID': requestIds.next(),
    },
    validateStatus: acceptedStatusCodes.isEmpty
        ? null
        : (status) =>
              status != null &&
              ((status >= 200 && status < 300) ||
                  acceptedStatusCodes.contains(status)),
  );

  Map<String, Object?> _jsonObject(Object? body) {
    Object? decoded = body;
    if (body is String) decoded = jsonDecode(body);
    if (body is Uint8List) decoded = jsonDecode(utf8.decode(body));
    if (body is List<int>) decoded = jsonDecode(utf8.decode(body));
    if (decoded is! Map) throw const FormatException('Expected JSON object');
    return Map<String, Object?>.from(decoded);
  }
}
