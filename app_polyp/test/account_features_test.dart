import 'dart:async';

import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/app/theme_controller.dart';
import 'package:app_polyp/features/account/account_api.dart';
import 'package:app_polyp/features/account/account_controller.dart';
import 'package:app_polyp/features/account/account_models.dart';
import 'package:app_polyp/features/account/account_state.dart';
import 'package:app_polyp/features/account/change_password_screen.dart';
import 'package:app_polyp/features/account/edit_profile_screen.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

ProviderContainer _container(
  FakeAccountApi accountApi, {
  FakeSessionStore? sessionStore,
}) {
  final container = ProviderContainer(
    overrides: [
      authApiProvider.overrideWithValue(FakeAuthApi()),
      authSessionStoreProvider.overrideWithValue(
        sessionStore ?? FakeSessionStore(),
      ),
      accountApiProvider.overrideWithValue(accountApi),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _authenticate(ProviderContainer container) => container
    .read(authControllerProvider.notifier)
    .login(const LoginRequest(email: 'an@example.com', password: 'secret-123'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M3 fullName update synchronizes AuthUser without logout', () async {
    const updated = AuthUser(
      id: 'user-1',
      fullName: 'Nguyễn Văn Bình',
      email: 'an@example.com',
      role: 'USER',
    );
    final api = FakeAccountApi()
      ..onUpdateProfile = (_) async => const ProfileUpdateResult(
        user: updated,
        reauthenticationRequired: false,
      );
    final store = FakeSessionStore();
    final container = _container(api, sessionStore: store);
    await _authenticate(container);

    final result = await container
        .read(accountControllerProvider.notifier)
        .updateProfile(
          const ProfileUpdateRequest(
            fullName: 'Nguyễn Văn Bình',
            email: 'an@example.com',
          ),
        );

    expect(result, ProfileUpdateOutcome.updated);
    expect(
      container.read(authControllerProvider).user?.fullName,
      updated.fullName,
    );
    expect(store.clearAllCalls, 0);
  });

  test(
    'M3 email update requires reauthentication and clears session',
    () async {
      const updated = AuthUser(
        id: 'user-1',
        fullName: 'Nguyễn Văn An',
        email: 'new@example.com',
        role: 'USER',
      );
      final api = FakeAccountApi()
        ..onUpdateProfile = (_) async => const ProfileUpdateResult(
          user: updated,
          reauthenticationRequired: true,
        );
      final store = FakeSessionStore();
      final container = _container(api, sessionStore: store);
      await _authenticate(container);

      final result = await container
          .read(accountControllerProvider.notifier)
          .updateProfile(
            const ProfileUpdateRequest(
              fullName: 'Nguyễn Văn An',
              email: 'NEW@EXAMPLE.COM',
            ),
          );

      expect(result, ProfileUpdateOutcome.reauthenticationRequired);
      final auth = container.read(authControllerProvider);
      expect(auth.status, AuthStatus.unauthenticated);
      expect(auth.emailHint, 'new@example.com');
      expect(auth.message, contains('email mới'));
      expect(store.clearAllCalls, 1);
    },
  );

  test('M3 duplicate email preserves safe server error', () async {
    final api = FakeAccountApi()
      ..onUpdateProfile = (_) async => throw const ApiException(
        statusCode: 409,
        code: 'EMAIL_ALREADY_EXISTS',
        message: 'Email đã được sử dụng.',
        fieldErrors: {'email': 'Email đã được sử dụng.'},
      );
    final container = _container(api);
    await _authenticate(container);

    await container
        .read(accountControllerProvider.notifier)
        .updateProfile(
          const ProfileUpdateRequest(
            fullName: 'Nguyễn Văn An',
            email: 'taken@example.com',
          ),
        );

    final state = container.read(accountControllerProvider);
    expect(state.status, AccountOperationStatus.failure);
    expect(state.fieldErrors['email'], 'Email đã được sử dụng.');
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
  });

  test('M3 profile double-submit is blocked', () async {
    final completer = Completer<ProfileUpdateResult>();
    final api = FakeAccountApi()..onUpdateProfile = (_) => completer.future;
    final container = _container(api);
    await _authenticate(container);
    const request = ProfileUpdateRequest(
      fullName: 'Nguyễn Văn An',
      email: 'an@example.com',
    );
    final controller = container.read(accountControllerProvider.notifier);

    final first = controller.updateProfile(request);
    final second = await controller.updateProfile(request);
    completer.complete(
      const ProfileUpdateResult(
        user: testUser,
        reauthenticationRequired: false,
      ),
    );
    await first;

    expect(second, isNull);
    expect(api.updateProfileCalls, 1);
  });

  test('M3 wrong current password uses stable friendly message', () async {
    final api = FakeAccountApi()
      ..onChangePassword = (_) async => throw const ApiException(
        statusCode: 400,
        code: 'CURRENT_PASSWORD_INCORRECT',
        message: 'Mật khẩu hiện tại không đúng.',
      );
    final container = _container(api);
    await _authenticate(container);

    final success = await container
        .read(accountControllerProvider.notifier)
        .changePassword(
          const PasswordChangeRequest(
            currentPassword: 'wrong',
            newPassword: 'NewPassword1',
            confirmPassword: 'NewPassword1',
          ),
        );

    expect(success, isFalse);
    expect(
      container.read(accountControllerProvider).message,
      'Mật khẩu hiện tại không đúng.',
    );
  });

  test('M3 password reuse error remains authenticated', () async {
    final api = FakeAccountApi()
      ..onChangePassword = (_) async => throw const ApiException(
        statusCode: 400,
        code: 'PASSWORD_REUSE_NOT_ALLOWED',
        message: 'Mật khẩu mới phải khác mật khẩu hiện tại.',
      );
    final container = _container(api);
    await _authenticate(container);

    await container
        .read(accountControllerProvider.notifier)
        .changePassword(
          const PasswordChangeRequest(
            currentPassword: 'OldPassword1',
            newPassword: 'OldPassword1',
            confirmPassword: 'OldPassword1',
          ),
        );

    expect(
      container.read(accountControllerProvider).message,
      contains('phải khác'),
    );
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
  });

  test(
    'M3 successful password change clears session and password state',
    () async {
      final store = FakeSessionStore();
      final container = _container(FakeAccountApi(), sessionStore: store);
      await _authenticate(container);

      final success = await container
          .read(accountControllerProvider.notifier)
          .changePassword(
            const PasswordChangeRequest(
              currentPassword: 'OldPassword1',
              newPassword: 'NewPassword2',
              confirmPassword: 'NewPassword2',
            ),
          );

      expect(success, isTrue);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
      expect(
        container.read(authControllerProvider).message,
        contains('thành công'),
      );
      expect(store.clearAllCalls, 1);
      expect(container.read(accountControllerProvider).fieldErrors, isEmpty);
    },
  );

  test('M3 sensitive logout preserves the selected theme preference', () async {
    SharedPreferences.setMockInitialValues({
      'polypvision-theme': AppThemePreference.dark.name,
    });
    final container = _container(FakeAccountApi());
    await _authenticate(container);
    container.read(themeControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(themeControllerProvider), AppThemePreference.dark);

    await container
        .read(accountControllerProvider.notifier)
        .changePassword(
          const PasswordChangeRequest(
            currentPassword: 'OldPassword1',
            newPassword: 'NewPassword2',
            confirmPassword: 'NewPassword2',
          ),
        );

    expect(container.read(themeControllerProvider), AppThemePreference.dark);
  });

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester, {
    required Widget screen,
    FakeAccountApi? accountApi,
  }) async {
    final container = _container(accountApi ?? FakeAccountApi());
    await _authenticate(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('M3 edit profile prefills authenticated user', (tester) async {
    await pumpScreen(tester, screen: const EditProfileScreen());

    final fullName = tester.widget<TextFormField>(
      find.byKey(const Key('profile-full-name')),
    );
    final email = tester.widget<TextFormField>(
      find.byKey(const Key('profile-email')),
    );
    expect(fullName.controller?.text, testUser.fullName);
    expect(email.controller?.text, testUser.email);
    expect(find.text('role'), findsNothing);
  });

  testWidgets('M3 edit profile validates name and email client-side', (
    tester,
  ) async {
    final api = FakeAccountApi();
    await pumpScreen(
      tester,
      screen: const EditProfileScreen(),
      accountApi: api,
    );
    await tester.enterText(find.byKey(const Key('profile-full-name')), 'A');
    await tester.enterText(find.byKey(const Key('profile-email')), 'invalid');
    await tester.tap(find.byKey(const Key('profile-submit')));
    await tester.pump();

    expect(find.text('Họ tên phải có từ 2 đến 100 ký tự.'), findsOneWidget);
    expect(find.text('Email chưa đúng định dạng.'), findsOneWidget);
    expect(api.updateProfileCalls, 0);
  });

  testWidgets('M3 duplicate email appears at the email field', (tester) async {
    final api = FakeAccountApi()
      ..onUpdateProfile = (_) async => throw const ApiException(
        statusCode: 409,
        code: 'EMAIL_ALREADY_EXISTS',
        message: 'Email đã được sử dụng.',
        fieldErrors: {'email': 'Email đã được sử dụng.'},
      );
    await pumpScreen(
      tester,
      screen: const EditProfileScreen(),
      accountApi: api,
    );
    await tester.enterText(
      find.byKey(const Key('profile-email')),
      'taken@example.com',
    );
    await tester.tap(find.byKey(const Key('profile-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Email đã được sử dụng.'), findsWidgets);
    expect(find.byKey(const Key('profile-error')), findsOneWidget);
  });

  testWidgets('M3 change password validates every client field', (
    tester,
  ) async {
    final api = FakeAccountApi();
    await pumpScreen(
      tester,
      screen: const ChangePasswordScreen(),
      accountApi: api,
    );
    await tester.tap(find.byKey(const Key('password-submit')));
    await tester.pump();

    expect(find.text('Vui lòng nhập mật khẩu hiện tại.'), findsOneWidget);
    expect(find.text('Mật khẩu phải có từ 8 đến 72 ký tự.'), findsOneWidget);
    expect(api.changePasswordCalls, 0);
  });

  testWidgets('M3 password controllers clear after failed API submit', (
    tester,
  ) async {
    final api = FakeAccountApi()
      ..onChangePassword = (_) async => throw const ApiException(
        statusCode: 400,
        code: 'CURRENT_PASSWORD_INCORRECT',
        message: 'Mật khẩu hiện tại không đúng.',
      );
    await pumpScreen(
      tester,
      screen: const ChangePasswordScreen(),
      accountApi: api,
    );
    await tester.enterText(
      find.byKey(const Key('password-current')),
      'WrongPassword1',
    );
    await tester.enterText(
      find.byKey(const Key('password-new')),
      'NewPassword2',
    );
    await tester.enterText(
      find.byKey(const Key('password-confirmation')),
      'NewPassword2',
    );
    await tester.tap(find.byKey(const Key('password-submit')));
    await tester.pumpAndSettle();

    for (final key in const [
      Key('password-current'),
      Key('password-new'),
      Key('password-confirmation'),
    ]) {
      final field = tester.widget<TextFormField>(find.byKey(key));
      expect(field.controller?.text, isEmpty);
    }
    expect(find.text('Mật khẩu hiện tại không đúng.'), findsOneWidget);
  });
}
