import 'package:app_polyp/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('M7 debug default is the Android emulator URL without a LAN IP', () {
    expect(AppConfig.apiBaseUrl, 'http://10.0.2.2:8080');
    expect(AppConfig.apiBaseUrl, isNot(contains('192.168.')));
    expect(
      AppConfig.validateApiBaseUrl(AppConfig.apiBaseUrl, isRelease: false),
      isNull,
    );
  });

  test('M7 debug accepts localhost and private LAN HTTP URLs', () {
    for (final url in [
      'http://localhost:8080',
      'http://10.0.2.2:8080',
      'http://192.168.1.20:8080',
      'http://172.16.0.5:8080',
    ]) {
      expect(
        AppConfig.validateApiBaseUrl(url, isRelease: false),
        isNull,
        reason: url,
      );
    }
  });

  test('M7 release accepts a public HTTPS URL', () {
    expect(
      AppConfig.validateApiBaseUrl(
        'https://api.polypvision.example',
        isRelease: true,
      ),
      isNull,
    );
  });

  test('M7 release rejects a missing URL and HTTP', () {
    expect(AppConfig.validateApiBaseUrl('', isRelease: true), isNotNull);
    expect(
      AppConfig.validateApiBaseUrl(
        'http://api.polypvision.example',
        isRelease: true,
      ),
      contains('HTTPS'),
    );
  });

  test('M7 release rejects localhost and emulator loopback', () {
    for (final url in [
      'https://localhost:8080',
      'https://api.local',
      'https://10.0.2.2:8080',
      'https://127.0.0.1:8080',
      'https://[::1]:8080',
    ]) {
      expect(
        AppConfig.validateApiBaseUrl(url, isRelease: true),
        isNotNull,
        reason: url,
      );
    }
  });

  test('M7 release rejects private and link-local IPv4 URLs', () {
    for (final url in [
      'https://10.20.30.40',
      'https://172.31.255.1',
      'https://192.168.50.10',
      'https://169.254.10.2',
    ]) {
      expect(
        AppConfig.validateApiBaseUrl(url, isRelease: true),
        isNotNull,
        reason: url,
      );
    }
  });

  test('M7 malformed and unsupported URLs are rejected in every build', () {
    for (final url in ['not-a-url', 'ftp://example.com', 'http:///missing']) {
      expect(
        AppConfig.validateApiBaseUrl(url, isRelease: false),
        isNotNull,
        reason: url,
      );
    }
  });
}
