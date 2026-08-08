import 'dart:io';

import 'package:app_polyp/app/legacy_polypvision_app.dart';
import 'package:app_polyp/app/theme_controller.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:app_polyp/navigation/app_router.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<
    ({ProviderContainer container, FakeAuthApi api, FakeSessionStore store})
  >
  pumpApp(
    WidgetTester tester, {
    bool authenticated = false,
    Size size = const Size(390, 844),
    Map<String, Object> preferences = const {},
    FakeAuthApi? fakeApi,
    FakeDashboardApi? fakeDashboardApi,
  }) async {
    SharedPreferences.setMockInitialValues(preferences);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    final api = fakeApi ?? FakeAuthApi();
    if (authenticated) api.onMe = () async => testUser;
    final store = FakeSessionStore();
    final dashboardApi = fakeDashboardApi ?? FakeDashboardApi();
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(api),
        authSessionStoreProvider.overrideWithValue(store),
        dashboardApiProvider.overrideWithValue(dashboardApi),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LegacyPolypVisionApp(),
      ),
    );
    await tester.pump();
    return (container: container, api: api, store: store);
  }

  Future<void> settleBootstrap(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
  }

  GoRouter routerOf(ProviderContainer container) =>
      container.read(appRouterProvider);

  testWidgets('23. guest cannot enter dashboard and redirect does not loop', (
    tester,
  ) async {
    final scope = await pumpApp(tester);
    await settleBootstrap(tester);

    routerOf(scope.container).go(AppRoutes.dashboard);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.byKey(const Key('compact-navigation-bar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('24. authenticated user visiting login goes to dashboard', (
    tester,
  ) async {
    final scope = await pumpApp(tester, authenticated: true);
    await settleBootstrap(tester);

    routerOf(scope.container).go(AppRoutes.login);
    await tester.pumpAndSettle();

    expect(find.text('Tổng quan hoạt động'), findsOneWidget);
    expect(find.byKey(const Key('login-submit')), findsNothing);
  });

  testWidgets('25. login is real UI and contains no M1 mock badge', (
    tester,
  ) async {
    await pumpApp(tester);
    await settleBootstrap(tester);

    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);
    expect(find.text('M1 giao diện thử nghiệm'), findsNothing);
  });

  testWidgets('26. login success reaches dashboard', (tester) async {
    await pumpApp(tester);
    await settleBootstrap(tester);

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'an@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'secret-123',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Tổng quan hoạt động'), findsOneWidget);
  });

  testWidgets('27. register displays server field errors', (tester) async {
    final api = FakeAuthApi()
      ..onRegister = (_) async => throw const ApiException(
        statusCode: 400,
        code: 'VALIDATION_ERROR',
        message: 'Dữ liệu không hợp lệ.',
        fieldErrors: {'email': 'Email đã được sử dụng.'},
      );
    final scope = await pumpApp(tester, fakeApi: api);
    await settleBootstrap(tester);
    routerOf(scope.container).go(AppRoutes.register);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('register-full-name')),
      'Nguyễn Văn An',
    );
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'an@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secret-123',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'secret-123',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Email đã được sử dụng.'), findsOneWidget);
    expect(find.byKey(const Key('register-error')), findsOneWidget);
  });

  testWidgets('28. successful register prefills email without auto-login', (
    tester,
  ) async {
    final scope = await pumpApp(tester);
    await settleBootstrap(tester);
    routerOf(scope.container).go(AppRoutes.register);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('register-full-name')),
      'Nguyễn Văn An',
    );
    await tester.enterText(
      find.byKey(const Key('register-email')),
      'AN@EXAMPLE.COM',
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'secret-123',
    );
    await tester.enterText(
      find.byKey(const Key('register-confirm-password')),
      'secret-123',
    );
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byKey(const Key('register-submit')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('login-email')),
    );
    expect(field.controller?.text, 'an@example.com');
    expect(
      scope.container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
  });

  testWidgets('29. Account renders the authenticated current user', (
    tester,
  ) async {
    final scope = await pumpApp(tester, authenticated: true);
    await settleBootstrap(tester);
    routerOf(scope.container).go(AppRoutes.account);
    await tester.pumpAndSettle();

    expect(find.text('Nguyễn Văn An'), findsOneWidget);
    expect(find.text('an@example.com'), findsOneWidget);
    expect(find.text('USER'), findsOneWidget);
    expect(find.text('mock@example.com'), findsNothing);
  });

  testWidgets('30. confirmed logout preserves theme preference', (
    tester,
  ) async {
    final scope = await pumpApp(
      tester,
      authenticated: true,
      preferences: const {'polypvision-theme': 'dark'},
    );
    await settleBootstrap(tester);
    routerOf(scope.container).go(AppRoutes.account);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('logout-button')),
      300,
    );

    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-logout')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(
      scope.container.read(themeControllerProvider),
      AppThemePreference.dark,
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('polypvision-theme'), 'dark');
  });

  testWidgets('31. Dashboard has the scientific-use disclaimer', (
    tester,
  ) async {
    final dashboardApi = FakeDashboardApi()
      ..onFetch = () async => testDashboard();
    await pumpApp(tester, authenticated: true, fakeDashboardApi: dashboardApi);
    await settleBootstrap(tester);
    await tester.drag(
      find.byKey(const Key('dashboard-data')),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'không thay thế đánh giá thực nghiệm khoa học của mô hình',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('mAP'), findsNothing);
    expect(find.textContaining('Dice'), findsNothing);
    expect(find.textContaining('IoU'), findsNothing);
  });

  testWidgets('32. unknown authenticated route has a safe error screen', (
    tester,
  ) async {
    final scope = await pumpApp(tester, authenticated: true);
    await settleBootstrap(tester);

    routerOf(scope.container).go('/route-khong-ton-tai');
    await tester.pumpAndSettle();

    expect(find.text('Đường dẫn không hợp lệ'), findsOneWidget);
    expect(find.textContaining('không tồn tại'), findsOneWidget);
  });

  testWidgets('33. bootstrap network failure offers retry instead of hanging', (
    tester,
  ) async {
    final api = FakeAuthApi()
      ..onMe = () async => throw const ApiException(
        code: 'CONNECTION_ERROR',
        message: 'Không kết nối được máy chủ.',
      );
    await pumpApp(tester, fakeApi: api);
    await settleBootstrap(tester);

    expect(find.text('Không thể kiểm tra phiên đăng nhập'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('34. phone and tablet navigation remain responsive', (
    tester,
  ) async {
    await pumpApp(tester, authenticated: true, size: const Size(1000, 900));
    await settleBootstrap(tester);

    final rail = tester.widget<NavigationRail>(
      find.byKey(const Key('expanded-navigation-rail')),
    );
    expect(rail.extended, isTrue);
    expect(tester.takeException(), isNull);
  });

  test('35. MockSessionController and mock auth badge are absent from lib', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(sources, isNot(contains('MockSessionController')));
    expect(sources, isNot(contains('mockSessionControllerProvider')));
    expect(sources, isNot(contains('M1 giao diện thử nghiệm')));
  });
}
