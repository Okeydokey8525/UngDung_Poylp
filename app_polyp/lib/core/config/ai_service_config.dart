import 'package:flutter/foundation.dart';

/// Configuration for Flutter's direct connection to the FastAPI AI service.
///
/// This is deliberately separate from [AppConfig] and `API_BASE_URL`, which
/// remain owned by the legacy Spring Boot flow during the migration.
final class AiServiceConfig {
  AiServiceConfig._(this.baseUrl);

  static const String environmentKey = 'AI_BASE_URL';
  static const String _configuredAiBaseUrl = String.fromEnvironment(
    environmentKey,
    defaultValue: '',
  );

  static const String debugDefaultAiBaseUrl = 'http://10.0.2.2:8000';

  final String baseUrl;

  factory AiServiceConfig.fromEnvironment() =>
      AiServiceConfig.fromValue(_configuredAiBaseUrl, isRelease: kReleaseMode);

  factory AiServiceConfig.fromValue(
    String configuredValue, {
    required bool isRelease,
  }) {
    final candidate = configuredValue.trim().isEmpty && !isRelease
        ? debugDefaultAiBaseUrl
        : configuredValue.trim();
    final error = validateBaseUrl(candidate, isRelease: isRelease);
    if (error != null) throw FormatException(error);
    return AiServiceConfig._(_removeTrailingSlashes(candidate));
  }

  static String? validateBaseUrl(String value, {required bool isRelease}) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'AI_BASE_URL chưa được cấu hình.';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'AI_BASE_URL không phải URL tuyệt đối hợp lệ.';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'AI_BASE_URL chỉ hỗ trợ giao thức HTTP hoặc HTTPS.';
    }
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
      return 'AI_BASE_URL không được chứa thông tin đăng nhập, query hoặc fragment.';
    }
    if (isRelease && uri.scheme != 'https') {
      return 'Bản release yêu cầu AI_BASE_URL sử dụng HTTPS.';
    }
    if (isRelease && _isDevelopmentHost(uri.host.toLowerCase())) {
      return 'Bản release không được kết nối tới máy chủ phát triển.';
    }
    return null;
  }

  static String _removeTrailingSlashes(String value) =>
      value.replaceFirst(RegExp(r'/+$'), '');

  static bool _isDevelopmentHost(String host) {
    if (host == 'localhost' ||
        host == '10.0.2.2' ||
        host == '::1' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local')) {
      return true;
    }

    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList(growable: false);
    if (octets.any((part) => part == null || part < 0 || part > 255)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }
}
