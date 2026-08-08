enum AiFailureKind { connection, timeout, cancelled, server, invalidResponse }

final class AiApiError {
  const AiApiError({
    required this.requestId,
    required this.status,
    required this.code,
    required this.message,
    required this.fieldErrors,
  });

  final String requestId;
  final int status;
  final String code;
  final String message;
  final Map<String, String> fieldErrors;
}

final class AiApiException implements Exception {
  const AiApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.requestId,
    this.fieldErrors = const {},
  });

  final AiFailureKind kind;
  final String message;
  final int? statusCode;
  final String? code;
  final String? requestId;
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}
