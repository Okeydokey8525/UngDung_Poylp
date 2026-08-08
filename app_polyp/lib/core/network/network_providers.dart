import 'dart:async';

import 'package:app_polyp/core/config/app_config.dart';
import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/csrf_interceptor.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class AuthSessionStore {
  void clearCsrf();
  Future<void> clearAll();
  void setUnauthorizedHandler(void Function()? handler);
}

class NetworkBundle implements AuthSessionStore {
  NetworkBundle({
    required this.dio,
    required this.cookieJar,
    required this.client,
    required this.csrf,
  });

  final Dio dio;
  final CookieJar cookieJar;
  final ApiClient client;
  final CsrfController csrf;
  void Function()? _unauthorizedHandler;

  void notifyUnauthorized() => _unauthorizedHandler?.call();

  @override
  void clearCsrf() => csrf.clear();

  @override
  Future<void> clearAll() async {
    csrf.clear();
    await cookieJar.deleteAll();
  }

  @override
  void setUnauthorizedHandler(void Function()? handler) {
    _unauthorizedHandler = handler;
  }
}

final networkBundleProvider = Provider<NetworkBundle>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {Headers.acceptHeader: 'application/json'},
    ),
  );
  final cookieJar = CookieJar();
  final client = ApiClient(dio);
  final csrf = CsrfController(client);
  final bundle = NetworkBundle(
    dio: dio,
    cookieJar: cookieJar,
    client: client,
    csrf: csrf,
  );

  dio.interceptors
    ..add(CookieManager(cookieJar))
    ..add(CsrfInterceptor(() => csrf.token))
    ..add(
      InterceptorsWrapper(
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            bundle.notifyUnauthorized();
          }
          handler.next(error);
        },
      ),
    );

  ref.onDispose(() {
    bundle.setUnauthorizedHandler(null);
    unawaited(cookieJar.deleteAll());
    dio.close(force: true);
  });
  return bundle;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ref.watch(networkBundleProvider).client,
);

final cookieJarProvider = Provider<CookieJar>(
  (ref) => ref.watch(networkBundleProvider).cookieJar,
);

final csrfControllerProvider = Provider<CsrfController>(
  (ref) => ref.watch(networkBundleProvider).csrf,
);

final authSessionStoreProvider = Provider<AuthSessionStore>(
  (ref) => ref.watch(networkBundleProvider),
);
