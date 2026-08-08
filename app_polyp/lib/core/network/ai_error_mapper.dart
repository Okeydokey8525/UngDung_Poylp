import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'ai_api_exception.dart';
import 'ai_request_id.dart';

abstract final class AiErrorMapper {
  static const String invalidResponseMessage =
      'Dịch vụ AI trả về phản hồi không hợp lệ.';

  static AiApiException fromDio(DioException exception) {
    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const AiApiException(
          kind: AiFailureKind.timeout,
          code: 'TIMEOUT',
          message: 'Quá thời gian xử lý.',
        );
      case DioExceptionType.connectionError:
        return const AiApiException(
          kind: AiFailureKind.connection,
          message: 'Không thể kết nối dịch vụ AI.',
        );
      case DioExceptionType.cancel:
        return const AiApiException(
          kind: AiFailureKind.cancelled,
          message: 'Yêu cầu đã được hủy.',
        );
      case DioExceptionType.badResponse:
        return _fromBadResponse(exception);
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return const AiApiException(
          kind: AiFailureKind.connection,
          message: 'Không thể kết nối dịch vụ AI.',
        );
    }
  }

  static AiApiException invalidResponse() => const AiApiException(
    kind: AiFailureKind.invalidResponse,
    code: 'INVALID_RESPONSE',
    message: invalidResponseMessage,
  );

  static AiApiError? parseEnvelope(Object? data) {
    final decoded = _decodeBody(data);
    if (decoded is! Map) return null;
    try {
      final map = Map<String, Object?>.from(decoded);
      final requestId = _requiredString(map, 'requestId');
      if (!AiRequestIdGenerator.isValid(requestId)) return null;
      final status = map['status'];
      final code = _requiredString(map, 'code');
      final message = _requiredString(map, 'message');
      final rawFields = map['fieldErrors'];
      if (status is! int || rawFields is! Map) return null;
      final fields = <String, String>{};
      for (final entry in rawFields.entries) {
        if (entry.key is! String || entry.value is! String) return null;
        fields[entry.key as String] = entry.value as String;
      }
      return AiApiError(
        requestId: requestId,
        status: status,
        code: code,
        message: message,
        fieldErrors: Map.unmodifiable(fields),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static AiApiException _fromBadResponse(DioException exception) {
    final envelope = parseEnvelope(exception.response?.data);
    if (envelope == null) return invalidResponse();
    return AiApiException(
      kind: AiFailureKind.server,
      statusCode: envelope.status,
      code: envelope.code,
      requestId: envelope.requestId,
      fieldErrors: envelope.fieldErrors,
      message: _safeMessageFor(envelope.code),
    );
  }

  static String _safeMessageFor(String code) => switch (code) {
    'VALIDATION_ERROR' => 'Dữ liệu gửi lên không hợp lệ.',
    'INVALID_IMAGE' => 'Tệp ảnh không hợp lệ.',
    'FILE_TOO_LARGE' => 'Ảnh vượt quá dung lượng cho phép.',
    'UNSUPPORTED_MEDIA_TYPE' => 'Định dạng ảnh không được hỗ trợ.',
    'MODEL_NOT_FOUND' => 'Không tìm thấy mô hình được yêu cầu.',
    'MODEL_NOT_READY' => 'Mô hình chưa sẵn sàng.',
    'INFERENCE_FAILED' => 'Dịch vụ AI không thể xử lý ảnh.',
    'TIMEOUT' => 'Quá thời gian xử lý.',
    'SERVICE_BUSY' => 'Dịch vụ AI đang bận, vui lòng thử lại.',
    'INTERNAL_ERROR' => 'Dịch vụ AI gặp lỗi nội bộ.',
    _ => invalidResponseMessage,
  };

  static Object? _decodeBody(Object? data) {
    if (data is Map) return data;
    try {
      if (data is String) return jsonDecode(data);
      if (data is Uint8List) return jsonDecode(utf8.decode(data));
      if (data is List<int>) return jsonDecode(utf8.decode(data));
    } on FormatException {
      return null;
    }
    return null;
  }

  static String _requiredString(Map<String, Object?> map, String field) {
    final value = map[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field is required');
    }
    return value;
  }
}
