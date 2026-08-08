import 'dart:async';

import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  bool _bootstrapStarted = false;
  bool _operationInProgress = false;
  late AuthRepository _api;
  late AuthSessionStore _sessionStore;

  @override
  AuthState build() {
    _api = ref.watch(authApiProvider);
    _sessionStore = ref.watch(authSessionStoreProvider);
    _sessionStore.setUnauthorizedHandler(_handleUnauthorized);
    ref.onDispose(() => _sessionStore.setUnauthorizedHandler(null));
    return const AuthState.checking();
  }

  Future<void> bootstrap({bool force = false}) async {
    if (_bootstrapStarted && !force) return;
    if (_operationInProgress) return;
    _bootstrapStarted = true;
    _operationInProgress = true;
    state = const AuthState.checking();
    try {
      final user = await _api.me();
      state = AuthState.authenticated(user);
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await _sessionStore.clearAll();
        state = const AuthState.unauthenticated();
      } else {
        state = AuthState.failure(
          message: error.message,
          requestId: error.requestId,
          bootstrapFailure: true,
        );
      }
    } catch (_) {
      state = const AuthState.failure(
        message: 'Đã xảy ra lỗi, vui lòng thử lại.',
        bootstrapFailure: true,
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<bool> login(LoginRequest request) async {
    if (_operationInProgress) return false;
    _operationInProgress = true;
    state = AuthState.authenticating(emailHint: request.email.trim());
    try {
      final user = await _api.login(request);
      _sessionStore.clearCsrf();
      await _api.fetchCsrf();
      state = AuthState.authenticated(user);
      return true;
    } on ApiException catch (error) {
      state = AuthState.failure(
        message: error.message,
        fieldErrors: error.fieldErrors,
        requestId: error.requestId,
        emailHint: request.email.trim(),
      );
      return false;
    } catch (_) {
      state = AuthState.failure(
        message: 'Đã xảy ra lỗi, vui lòng thử lại.',
        emailHint: request.email.trim(),
      );
      return false;
    } finally {
      _operationInProgress = false;
    }
  }

  Future<bool> register(RegisterRequest request) async {
    if (_operationInProgress) return false;
    _operationInProgress = true;
    state = AuthState.authenticating(emailHint: request.email.trim());
    try {
      final result = await _api.register(request);
      state = AuthState.unauthenticated(
        message: result.message,
        emailHint: result.email,
      );
      return true;
    } on ApiException catch (error) {
      state = AuthState.failure(
        message: error.message,
        fieldErrors: error.fieldErrors,
        requestId: error.requestId,
        emailHint: request.email.trim(),
      );
      return false;
    } catch (_) {
      state = AuthState.failure(
        message: 'Đã xảy ra lỗi, vui lòng thử lại.',
        emailHint: request.email.trim(),
      );
      return false;
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> logout() async {
    if (_operationInProgress) return;
    _operationInProgress = true;
    try {
      await _api.logout();
    } catch (_) {
      // A local sign-out remains available when the server/session is unavailable.
    } finally {
      await _sessionStore.clearAll();
      state = const AuthState.unauthenticated();
      _operationInProgress = false;
    }
  }

  void updateCurrentUser(AuthUser user) {
    if (state.status == AuthStatus.authenticated) {
      state = AuthState.authenticated(user);
    }
  }

  Future<void> clearSessionAfterSensitiveChange({
    required String message,
    String? emailHint,
  }) async {
    await _sessionStore.clearAll();
    state = AuthState.unauthenticated(message: message, emailHint: emailHint);
  }

  void clearOperationError() {
    if (state.status == AuthStatus.failure && !state.bootstrapFailure) {
      state = AuthState.unauthenticated(emailHint: state.emailHint);
    }
  }

  void _handleUnauthorized() {
    if (state.status != AuthStatus.authenticated) return;
    state = const AuthState.unauthenticated(
      message: 'Phiên đăng nhập đã hết hạn.',
    );
    unawaited(_sessionStore.clearAll());
  }

  void expireSessionForTesting() => _handleUnauthorized();
}
