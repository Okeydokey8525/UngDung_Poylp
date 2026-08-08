class ApiErrorResponse {
  const ApiErrorResponse({
    required this.status,
    required this.code,
    required this.message,
    this.fieldErrors = const {},
    this.requestId,
  });

  factory ApiErrorResponse.fromJson(Map<String, dynamic> json) {
    final rawFieldErrors = json['fieldErrors'];
    final fieldErrors = <String, String>{};
    if (rawFieldErrors is Map) {
      for (final entry in rawFieldErrors.entries) {
        if (entry.key is String && entry.value is String) {
          fieldErrors[entry.key as String] = entry.value as String;
        }
      }
    }

    return ApiErrorResponse(
      status: json['status'] is num ? (json['status'] as num).toInt() : 0,
      code: json['code'] is String ? json['code'] as String : 'UNKNOWN_ERROR',
      message: json['message'] is String
          ? json['message'] as String
          : 'Đã xảy ra lỗi, vui lòng thử lại.',
      fieldErrors: fieldErrors,
      requestId: json['requestId'] is String
          ? json['requestId'] as String
          : null,
    );
  }

  final int status;
  final String code;
  final String message;
  final Map<String, String> fieldErrors;
  final String? requestId;
}
