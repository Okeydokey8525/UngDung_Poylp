import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const String debugDefaultApiBaseUrl = 'http://10.0.2.2:8080';

  static String get apiBaseUrl =>
      _configuredApiBaseUrl.trim().isEmpty && !kReleaseMode
      ? debugDefaultApiBaseUrl
      : _configuredApiBaseUrl.trim();

  static String? get validationError =>
      validateApiBaseUrl(apiBaseUrl, isRelease: kReleaseMode);

  static String? validateApiBaseUrl(String value, {required bool isRelease}) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return 'API_BASE_URL chưa được cấu hình.';
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'API_BASE_URL không phải URL tuyệt đối hợp lệ.';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'API_BASE_URL chỉ hỗ trợ giao thức HTTP hoặc HTTPS.';
    }

    if (!isRelease) return null;

    if (uri.scheme != 'https') {
      return 'Bản release yêu cầu API_BASE_URL sử dụng HTTPS.';
    }

    final host = uri.host.toLowerCase();
    if (_isDevelopmentHost(host)) {
      return 'Bản release không được kết nối tới máy chủ phát triển.';
    }
    return null;
  }

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

  static bool get showDebugInfo => kDebugMode;
}
