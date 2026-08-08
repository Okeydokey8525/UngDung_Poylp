import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/csrf_token.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class AuthRepository {
  Future<CsrfToken> fetchCsrf();
  Future<RegisterResult> register(RegisterRequest request);
  Future<AuthUser> login(LoginRequest request);
  Future<AuthUser> me();
  Future<void> logout();
}

class AuthApi implements AuthRepository {
  const AuthApi(this._client, this._csrf);

  final ApiClient _client;
  final CsrfController _csrf;

  @override
  Future<CsrfToken> fetchCsrf() => _csrf.fetch();

  @override
  Future<RegisterResult> register(RegisterRequest request) async {
    await _csrf.ensure();
    final json = await _client.postJson(
      '/api/v1/auth/register',
      data: request.toJson(),
    );
    try {
      return RegisterResult.fromJson(json);
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }
  }

  @override
  Future<AuthUser> login(LoginRequest request) async {
    await _csrf.ensure();
    final json = await _client.postJson(
      '/api/v1/auth/login',
      data: request.toJson(),
    );
    final user = json['user'];
    if (user is! Map) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }
    try {
      return AuthUser.fromJson(Map<String, dynamic>.from(user));
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }
  }

  @override
  Future<AuthUser> me() async {
    final json = await _client.getJson('/api/v1/me');
    try {
      return AuthUser.fromJson(json);
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }
  }

  @override
  Future<void> logout() async {
    await _csrf.ensure();
    try {
      await _client.postNoContent('/api/v1/auth/logout');
    } on ApiException catch (error) {
      if (error.code != 'CSRF_INVALID') rethrow;
      _csrf.clear();
      await _csrf.ensure();
      await _client.postNoContent('/api/v1/auth/logout');
    }
  }
}

final authApiProvider = Provider<AuthRepository>(
  (ref) =>
      AuthApi(ref.watch(apiClientProvider), ref.watch(csrfControllerProvider)),
);
