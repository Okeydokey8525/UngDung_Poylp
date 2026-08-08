import 'dart:convert';

import 'package:app_polyp/core/network/api_error_response.dart';
import 'package:dio/dio.dart';

class ApiException implements Exception {
  const ApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.fieldErrors = const {},
    this.requestId,
  });

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          code: 'TIMEOUT',
          message: 'Máy chủ phản hồi quá thời gian.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          code: 'CONNECTION_ERROR',
          message: 'Không kết nối được máy chủ.',
        );
      case DioExceptionType.badResponse:
        return _fromResponse(error.response);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return const ApiException(
          code: 'UNKNOWN_ERROR',
          message: 'Đã xảy ra lỗi, vui lòng thử lại.',
        );
    }
  }

  factory ApiException.fromResponse(Response<dynamic> response) =>
      _fromResponse(response);

  static ApiException _fromResponse(Response<dynamic>? response) {
    if (response == null || !_hasJsonContentType(response)) {
      return const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }

    final data = _jsonObject(response.data);
    if (data == null) {
      return const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }

    final error = ApiErrorResponse.fromJson(data);
    return ApiException(
      statusCode: response.statusCode ?? error.status,
      code: error.code,
      message: _safeMessage(error.code, error.message),
      fieldErrors: error.fieldErrors,
      requestId: error.requestId,
    );
  }

  static bool _hasJsonContentType(Response<dynamic> response) {
    final value = response.headers.value(Headers.contentTypeHeader);
    return value?.toLowerCase().contains('application/json') ?? false;
  }

  static Map<String, dynamic>? _jsonObject(dynamic data) {
    try {
      final dynamic decoded = switch (data) {
        Map<dynamic, dynamic>() => data,
        List<int>() => jsonDecode(utf8.decode(data)),
        String() => jsonDecode(data),
        _ => null,
      };
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static String _safeMessage(String code, String fallback) {
    return switch (code) {
      'INVALID_CREDENTIALS' => 'Email hoặc mật khẩu không đúng.',
      'ACCOUNT_DISABLED' => 'Tài khoản đã bị khóa.',
      'EMAIL_ALREADY_EXISTS' => 'Email đã được sử dụng.',
      'VALIDATION_ERROR' => 'Dữ liệu không hợp lệ.',
      'UNAUTHENTICATED' => 'Phiên đăng nhập đã hết hạn.',
      'CSRF_INVALID' => 'Phiên bảo mật không hợp lệ, vui lòng thử lại.',
      'CURRENT_PASSWORD_INCORRECT' => 'Mật khẩu hiện tại không đúng.',
      'PASSWORD_REUSE_NOT_ALLOWED' =>
        'Mật khẩu mới phải khác mật khẩu hiện tại.',
      'EMPTY_FILE' => 'Vui lòng chọn một ảnh không rỗng.',
      'FILE_TOO_LARGE' => 'Dung lượng ảnh vượt quá 10 MB.',
      'UNSUPPORTED_MEDIA_TYPE' => 'Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG.',
      'INVALID_IMAGE' => 'Tệp đã chọn không phải ảnh hợp lệ.',
      'INVALID_MODEL' => 'Mô hình được chọn không được hỗ trợ.',
      'AI_SERVICE_UNAVAILABLE' =>
        'Dịch vụ AI hiện không khả dụng. Vui lòng thử lại sau.',
      'MODEL_UNAVAILABLE' => 'Mô hình được chọn hiện không khả dụng.',
      'AI_SERVICE_TIMEOUT' => 'Dịch vụ AI phản hồi quá thời gian.',
      'MODEL_RESPONSE_MISMATCH' =>
        'Dịch vụ AI trả về kết quả từ mô hình không đúng yêu cầu.',
      'BASELINE_MODEL_UNAVAILABLE' => 'Mô hình Baseline hiện không khả dụng.',
      'VMAMBA_MODEL_UNAVAILABLE' => 'Mô hình VMamba hiện không khả dụng.',
      'BASELINE_TIMEOUT' => 'Lượt inference Baseline phản hồi quá thời gian.',
      'VMAMBA_TIMEOUT' => 'Lượt inference VMamba phản hồi quá thời gian.',
      'INCOMPLETE_COMPARISON' =>
        'Phiên so sánh không đầy đủ hoặc dữ liệu không nhất quán.',
      'RESOURCE_NOT_FOUND' => 'Không tìm thấy kết quả phân tích.',
      'FILE_NOT_FOUND' => 'Không tìm thấy file ảnh đã yêu cầu.',
      'ACCESS_DENIED' => 'Bạn không có quyền truy cập tài nguyên này.',
      'COMPARISON_RESULT_REQUIRES_GROUP_DELETE' =>
        'Kết quả thuộc phiên so sánh phải được xóa theo cả nhóm.',
      _ =>
        fallback.trim().isEmpty ? 'Đã xảy ra lỗi, vui lòng thử lại.' : fallback,
    };
  }

  final int? statusCode;
  final String? code;
  final String message;
  final Map<String, String> fieldErrors;
  final String? requestId;

  bool get isUnauthenticated => statusCode == 401 || code == 'UNAUTHENTICATED';
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}
