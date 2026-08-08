import 'dart:convert';

import 'package:app_polyp/core/config/app_config.dart';
import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/csrf_interceptor.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/account/account_api.dart';
import 'package:app_polyp/features/account/account_models.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('1. API client uses AppConfig base URL', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(apiClientProvider).baseUrl, AppConfig.apiBaseUrl);
  });

  test('2. one in-memory CookieJar is shared by the network bundle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      identical(
        container.read(cookieJarProvider),
        container.read(networkBundleProvider).cookieJar,
      ),
      isTrue,
    );
  });

  test('3. CSRF response is parsed and retained in memory', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = FakeHttpClientAdapter(
      (_) => jsonResponse({
        'token': 'abc',
        'headerName': 'X-CSRF-TOKEN',
        'parameterName': '_csrf',
      }),
    );
    final controller = CsrfController(ApiClient(dio));

    final token = await controller.fetch();

    expect(token.token, 'abc');
    expect(token.headerName, 'X-CSRF-TOKEN');
    expect(controller.token, same(token));
  });

  test('4. unsafe mutation includes the current CSRF header', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter((options) {
      if (options.path.endsWith('/csrf')) {
        return jsonResponse({
          'token': 'abc',
          'headerName': 'X-CSRF-TOKEN',
          'parameterName': '_csrf',
        });
      }
      return jsonResponse({'ok': true});
    });
    dio.httpClientAdapter = adapter;
    final csrf = CsrfController(ApiClient(dio));
    dio.interceptors.add(CsrfInterceptor(() => csrf.token));

    await csrf.fetch();
    await dio.post<dynamic>('/mutation', data: const {'value': 1});

    expect(adapter.requests.last.headers['X-CSRF-TOKEN'], 'abc');
  });

  test('5. GET requests do not include a CSRF header', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter(
      (_) => jsonResponse({
        'token': 'abc',
        'headerName': 'X-CSRF-TOKEN',
        'parameterName': '_csrf',
      }),
    );
    dio.httpClientAdapter = adapter;
    final csrf = CsrfController(ApiClient(dio));
    dio.interceptors.add(CsrfInterceptor(() => csrf.token));

    await csrf.fetch();
    await dio.get<dynamic>('/safe');

    expect(adapter.requests.last.headers.containsKey('X-CSRF-TOKEN'), isFalse);
  });

  test('6. login sends the exact JSON contract', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter((options) {
      if (options.path.endsWith('/csrf')) {
        return jsonResponse({
          'token': 'abc',
          'headerName': 'X-CSRF-TOKEN',
          'parameterName': '_csrf',
        });
      }
      return jsonResponse({
        'user': {
          'id': 'user-1',
          'fullName': 'Nguyễn An',
          'email': 'an@example.com',
          'role': 'USER',
        },
      });
    });
    dio.httpClientAdapter = adapter;
    final client = ApiClient(dio);
    final api = AuthApi(client, CsrfController(client));

    await api.login(
      const LoginRequest(email: ' AN@EXAMPLE.COM ', password: 'secret-123'),
    );

    expect(adapter.requests.last.data, {
      'email': 'an@example.com',
      'password': 'secret-123',
    });
  });

  test('7. register JSON cannot contain role or enabled', () {
    final json = const RegisterRequest(
      fullName: 'Nguyễn An',
      email: 'AN@example.com',
      password: 'secret-123',
      confirmPassword: 'secret-123',
      acceptedTerms: true,
    ).toJson();

    expect(json['email'], 'an@example.com');
    expect(json.containsKey('role'), isFalse);
    expect(json.containsKey('enabled'), isFalse);
  });

  test('8. timeout is converted to a friendly Vietnamese error', () {
    final error = ApiException.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/api/v1/me'),
        type: DioExceptionType.receiveTimeout,
      ),
    );

    expect(error.message, 'Máy chủ phản hồi quá thời gian.');
    expect(error.toString(), isNot(contains('DioException')));
  });

  test('9. non-JSON response is rejected safely', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = FakeHttpClientAdapter(
      (_) => ResponseBody.fromString(
        '<html>login</html>',
        200,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      ),
    );

    expect(
      () => ApiClient(dio).getJson('/api/v1/me'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Máy chủ trả về phản hồi không hợp lệ.',
        ),
      ),
    );
  });

  test('10. 401 JSON is mapped without exposing raw response data', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = FakeHttpClientAdapter(
      (_) => jsonResponse({
        'status': 401,
        'code': 'INVALID_CREDENTIALS',
        'message': 'safe',
        'fieldErrors': <String, String>{},
        'requestId': 'req-1',
      }, statusCode: 401),
    );

    expect(
      () => ApiClient(dio).postJson('/api/v1/auth/login'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', 401)
            .having(
              (error) => error.message,
              'message',
              'Email hoặc mật khẩu không đúng.',
            )
            .having((error) => error.requestId, 'requestId', 'req-1'),
      ),
    );
  });

  test('M3 dashboard API uses authenticated GET contract', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter(
      (_) => jsonResponse({
        'summary': {'totalInferenceCount': 2},
        'dailyUsage': [],
        'modelUsage': {'baseline': 2, 'vmamba': 0},
        'predictionUsage': {'detected': 1, 'notDetected': 1},
        'recentActivities': [],
        'disclaimer': 'Thống kê.',
      }),
    );
    dio.httpClientAdapter = adapter;

    final dashboard = await DashboardApi(ApiClient(dio)).fetchDashboard();

    expect(adapter.requests.single.method, 'GET');
    expect(adapter.requests.single.path, '/api/v1/dashboard');
    expect(dashboard.summary.totalInferenceCount, 2);
  });

  test('M3 profile API fetches CSRF and sends normalized PATCH JSON', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter((options) {
      if (options.path.endsWith('/csrf')) {
        return jsonResponse({
          'token': 'csrf-profile',
          'headerName': 'X-CSRF-TOKEN',
          'parameterName': '_csrf',
        });
      }
      return jsonResponse({
        'user': {
          'id': 'user-1',
          'fullName': 'Nguyễn An',
          'email': 'new@example.com',
          'role': 'USER',
        },
        'reauthenticationRequired': true,
      });
    });
    dio.httpClientAdapter = adapter;
    final client = ApiClient(dio);
    final csrf = CsrfController(client);
    dio.interceptors.add(CsrfInterceptor(() => csrf.token));

    final result = await AccountApi(client, csrf).updateProfile(
      const ProfileUpdateRequest(
        fullName: ' Nguyễn An ',
        email: ' NEW@EXAMPLE.COM ',
      ),
    );

    final request = adapter.requests.last;
    expect(request.method, 'PATCH');
    expect(request.path, '/api/v1/me');
    expect(request.headers['X-CSRF-TOKEN'], 'csrf-profile');
    expect(request.data, {'fullName': 'Nguyễn An', 'email': 'new@example.com'});
    expect(result.reauthenticationRequired, isTrue);
  });

  test('M3 password API sends CSRF-protected PUT contract', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter((options) {
      if (options.path.endsWith('/csrf')) {
        return jsonResponse({
          'token': 'csrf-password',
          'headerName': 'X-CSRF-TOKEN',
          'parameterName': '_csrf',
        });
      }
      return ResponseBody.fromString('', 204);
    });
    dio.httpClientAdapter = adapter;
    final client = ApiClient(dio);
    final csrf = CsrfController(client);
    dio.interceptors.add(CsrfInterceptor(() => csrf.token));

    await AccountApi(client, csrf).changePassword(
      const PasswordChangeRequest(
        currentPassword: 'OldPassword1',
        newPassword: 'NewPassword2',
        confirmPassword: 'NewPassword2',
      ),
    );

    final request = adapter.requests.last;
    expect(request.method, 'PUT');
    expect(request.path, '/api/v1/me/password');
    expect(request.headers['X-CSRF-TOKEN'], 'csrf-password');
    expect(request.data, {
      'currentPassword': 'OldPassword1',
      'newPassword': 'NewPassword2',
      'confirmPassword': 'NewPassword2',
    });
  });

  test(
    'image bytes request overrides Accept and keeps ResponseType.bytes',
    () async {
      late RequestOptions captured;
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://example.test',
          headers: const {Headers.acceptHeader: 'application/json'},
        ),
      );
      dio.httpClientAdapter = FakeHttpClientAdapter((options) {
        captured = options;
        return ResponseBody.fromBytes(
          const [0xff, 0xd8, 0xff, 0xd9],
          200,
          headers: {
            Headers.contentTypeHeader: ['image/jpeg; charset=binary'],
          },
        );
      });

      final bytes = await ApiClient(dio).getBytes('/image.jpg');

      expect(bytes, [0xff, 0xd8, 0xff, 0xd9]);
      expect(captured.responseType, ResponseType.bytes);
      expect(
        captured.headers[Headers.acceptHeader],
        'image/*, application/json',
      );
    },
  );

  test('PNG bytes with a Content-Type parameter are accepted', () async {
    const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1];
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = FakeHttpClientAdapter(
      (_) => ResponseBody.fromBytes(
        png,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png; name=result.png'],
        },
      ),
    );

    expect(await ApiClient(dio).getBytes('/image.png'), png);
  });

  for (final value in [
    (401, 'UNAUTHENTICATED'),
    (403, 'ACCESS_DENIED'),
    (404, 'FILE_NOT_FOUND'),
  ]) {
    test('JSON ${value.$1} bytes from an image request are parsed', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
      dio.httpClientAdapter = FakeHttpClientAdapter(
        (_) => ResponseBody.fromBytes(
          utf8.encode(
            jsonEncode({
              'status': value.$1,
              'code': value.$2,
              'message': 'Thông báo an toàn',
              'fieldErrors': <String, String>{},
              'requestId': 'image-request-id',
            }),
          ),
          value.$1,
          headers: {
            Headers.contentTypeHeader: ['application/json; charset=utf-8'],
          },
        ),
      );

      await expectLater(
        ApiClient(dio).getBytes('/protected-image'),
        throwsA(
          isA<ApiException>()
              .having((error) => error.statusCode, 'status', value.$1)
              .having((error) => error.code, 'code', value.$2)
              .having(
                (error) => error.requestId,
                'requestId',
                'image-request-id',
              ),
        ),
      );
    });
  }

  test('invalid image bytes are rejected before Image.memory', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = FakeHttpClientAdapter(
      (_) => ResponseBody.fromBytes(
        const [1, 2, 3, 4],
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png; charset=binary'],
        },
      ),
    );

    await expectLater(
      ApiClient(dio).getBytes('/broken-image'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'Dữ liệu ảnh từ máy chủ không hợp lệ.',
        ),
      ),
    );
  });

  test('malformed JSON bytes from an image error fail safely', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = FakeHttpClientAdapter(
      (_) => ResponseBody.fromBytes(
        const [0xff, 0xfe, 0xfd],
        404,
        headers: {
          Headers.contentTypeHeader: ['application/json; charset=utf-8'],
        },
      ),
    );

    await expectLater(
      ApiClient(dio).getBytes('/invalid-json-error'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'INVALID_RESPONSE',
        ),
      ),
    );
  });
}
