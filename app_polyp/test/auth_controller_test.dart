import 'dart:async';

import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ProviderContainer createContainer(
  FakeAuthApi api,
  FakeSessionStore sessionStore,
) {
  final container = ProviderContainer(
    overrides: [
      authApiProvider.overrideWithValue(api),
      authSessionStoreProvider.overrideWithValue(sessionStore),
    ],
  );
  addTearDown(container.dispose);
  container.read(authControllerProvider);
  return container;
}

void main() {
  test('11. bootstrap 401 becomes unauthenticated', () async {
    final api = FakeAuthApi();
    final store = FakeSessionStore();
    final container = createContainer(api, store);

    await container.read(authControllerProvider.notifier).bootstrap();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(store.clearAllCalls, 1);
  });

  test('12. successful bootstrap retains the current user', () async {
    final api = FakeAuthApi()..onMe = () async => testUser;
    final container = createContainer(api, FakeSessionStore());

    await container.read(authControllerProvider.notifier).bootstrap();

    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.authenticated);
    expect(state.user, same(testUser));
  });

  test('13. successful login stores user and refreshes CSRF', () async {
    final api = FakeAuthApi();
    final store = FakeSessionStore();
    final container = createContainer(api, store);

    final success = await container
        .read(authControllerProvider.notifier)
        .login(
          const LoginRequest(email: 'an@example.com', password: 'secret-123'),
        );

    expect(success, isTrue);
    expect(container.read(authControllerProvider).user, same(testUser));
    expect(store.clearCsrfCalls, 1);
    expect(api.csrfCalls, 1);
  });

  test('14. invalid credentials expose only the safe message', () async {
    final api = FakeAuthApi()
      ..onLogin = (_) async => throw const ApiException(
        statusCode: 401,
        code: 'INVALID_CREDENTIALS',
        message: 'Email hoặc mật khẩu không đúng.',
      );
    final container = createContainer(api, FakeSessionStore());

    await container
        .read(authControllerProvider.notifier)
        .login(
          const LoginRequest(
            email: 'missing@example.com',
            password: 'secret-123',
          ),
        );

    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.failure);
    expect(state.message, 'Email hoặc mật khẩu không đúng.');
    expect(state.user, isNull);
  });

  test('15. disabled account shows the expected message', () async {
    final api = FakeAuthApi()
      ..onLogin = (_) async => throw const ApiException(
        statusCode: 403,
        code: 'ACCOUNT_DISABLED',
        message: 'Tài khoản đã bị khóa.',
      );
    final container = createContainer(api, FakeSessionStore());

    await container
        .read(authControllerProvider.notifier)
        .login(
          const LoginRequest(
            email: 'locked@example.com',
            password: 'secret-123',
          ),
        );

    expect(
      container.read(authControllerProvider).message,
      'Tài khoản đã bị khóa.',
    );
  });

  test('16. register preserves server field errors', () async {
    final api = FakeAuthApi()
      ..onRegister = (_) async => throw const ApiException(
        statusCode: 400,
        code: 'VALIDATION_ERROR',
        message: 'Dữ liệu không hợp lệ.',
        fieldErrors: {'email': 'Email không hợp lệ.'},
        requestId: 'req-fields',
      );
    final container = createContainer(api, FakeSessionStore());

    await container
        .read(authControllerProvider.notifier)
        .register(
          const RegisterRequest(
            fullName: 'Nguyễn An',
            email: 'bad',
            password: 'secret-123',
            confirmPassword: 'secret-123',
            acceptedTerms: true,
          ),
        );

    final state = container.read(authControllerProvider);
    expect(state.fieldErrors['email'], 'Email không hợp lệ.');
    expect(state.requestId, 'req-fields');
  });

  test('17. concurrent login submission is blocked', () async {
    final completer = Completer<AuthUser>();
    final api = FakeAuthApi()..onLogin = (_) => completer.future;
    final container = createContainer(api, FakeSessionStore());
    const request = LoginRequest(
      email: 'an@example.com',
      password: 'secret-123',
    );

    final first = container
        .read(authControllerProvider.notifier)
        .login(request);
    final second = await container
        .read(authControllerProvider.notifier)
        .login(request);
    completer.complete(testUser);
    await first;

    expect(second, isFalse);
    expect(api.loginCalls, 1);
  });

  test('18. password is never retained in auth state after submit', () async {
    const password = 'do-not-retain-this-password';
    final container = createContainer(FakeAuthApi(), FakeSessionStore());

    await container
        .read(authControllerProvider.notifier)
        .login(const LoginRequest(email: 'an@example.com', password: password));

    final state = container.read(authControllerProvider);
    expect(state.message, isNot(contains(password)));
    expect(state.fieldErrors.values.join(), isNot(contains(password)));
    expect(state.user?.email, 'an@example.com');
  });

  test('19. logout clears cookie, CSRF, and auth state', () async {
    final api = FakeAuthApi();
    final store = FakeSessionStore();
    final container = createContainer(api, store);
    final controller = container.read(authControllerProvider.notifier);
    await controller.login(
      const LoginRequest(email: 'an@example.com', password: 'secret-123'),
    );

    await controller.logout();

    expect(api.logoutCalls, 1);
    expect(store.clearAllCalls, 1);
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
  });

  test('20. a 401 after authentication expires the local session', () async {
    final store = FakeSessionStore();
    final container = createContainer(FakeAuthApi(), store);
    final controller = container.read(authControllerProvider.notifier);
    await controller.login(
      const LoginRequest(email: 'an@example.com', password: 'secret-123'),
    );

    store.unauthorizedHandler?.call();
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(
      container.read(authControllerProvider).message,
      'Phiên đăng nhập đã hết hạn.',
    );
    expect(store.clearAllCalls, 1);
  });

  test('21. an ordinary 403 does not sign out an authenticated user', () async {
    final store = FakeSessionStore();
    final container = createContainer(FakeAuthApi(), store);
    final controller = container.read(authControllerProvider.notifier);
    await controller.login(
      const LoginRequest(email: 'an@example.com', password: 'secret-123'),
    );

    const forbidden = ApiException(
      statusCode: 403,
      code: 'ACCESS_DENIED',
      message: 'Bạn không có quyền thực hiện thao tác này.',
    );
    expect(forbidden.isForbidden, isTrue);

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
    expect(store.clearAllCalls, 0);
  });

  test(
    '22. bootstrap network failure is retryable and never authenticates',
    () async {
      final api = FakeAuthApi()
        ..onMe = () async => throw const ApiException(
          code: 'CONNECTION_ERROR',
          message: 'Không kết nối được máy chủ.',
        );
      final container = createContainer(api, FakeSessionStore());

      await container.read(authControllerProvider.notifier).bootstrap();

      final state = container.read(authControllerProvider);
      expect(state.status, AuthStatus.failure);
      expect(state.bootstrapFailure, isTrue);
      expect(state.message, 'Không kết nối được máy chủ.');
      expect(state.user, isNull);
    },
  );
}
