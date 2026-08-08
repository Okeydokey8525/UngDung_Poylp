import 'dart:async';
import 'dart:io';

import 'package:app_polyp/app/app_theme.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/dashboard/dashboard_models.dart';
import 'package:app_polyp/features/dashboard/dashboard_screen.dart';
import 'package:app_polyp/features/dashboard/dashboard_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ProviderContainer _container(
  FakeDashboardApi dashboardApi, {
  FakeSessionStore? sessionStore,
}) {
  final container = ProviderContainer(
    overrides: [
      authApiProvider.overrideWithValue(FakeAuthApi()),
      authSessionStoreProvider.overrideWithValue(
        sessionStore ?? FakeSessionStore(),
      ),
      dashboardApiProvider.overrideWithValue(dashboardApi),
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

  test('M3 dashboard API response parses into typed models', () {
    final dashboard = UserDashboard.fromJson({
      'summary': {
        'singleAnalysisCount': 3,
        'comparisonSessionCount': 1,
        'totalInferenceCount': 5,
        'detectedCount': 4,
        'averageProcessingTimeMs': 148.5,
        'averageDetectedConfidence': 0.624,
        'totalMaskCount': 7,
        'detectedRate': 0.8,
        'mostUsedModel': 'YOLO26n-seg',
      },
      'dailyUsage': [
        {'date': '2026-07-31', 'count': 5},
      ],
      'modelUsage': {'baseline': 3, 'vmamba': 2},
      'predictionUsage': {'detected': 4, 'notDetected': 1},
      'recentActivities': [
        {
          'id': 'd-1',
          'type': 'DIAGNOSIS',
          'fileName': 'sample.jpg',
          'modelType': 'YOLO26n-seg',
          'detected': true,
          'confidence': 0.624,
          'maskCount': 2,
          'processingTimeMs': 148.5,
          'createdAt': '2026-07-31T09:30:00Z',
        },
      ],
      'disclaimer': 'Thống kê sử dụng.',
    });

    expect(dashboard.summary.totalInferenceCount, 5);
    expect(dashboard.summary.averageDetectedConfidence, 0.624);
    expect(dashboard.dailyUsage.single.date, DateTime(2026, 7, 31));
    expect(dashboard.modelUsage.vmamba, 2);
    expect(
      dashboard.recentActivities.single.type,
      RecentActivityType.diagnosis,
    );
  });

  test('M3 dashboard missing and null fields use safe defaults', () {
    final dashboard = UserDashboard.fromJson({
      'summary': {
        'totalInferenceCount': -1,
        'detectedRate': 7,
        'averageDetectedConfidence': null,
      },
      'dailyUsage': null,
      'recentActivities': [
        {'fileName': null, 'confidence': -2},
      ],
    });

    expect(dashboard.summary.totalInferenceCount, 0);
    expect(dashboard.summary.detectedRate, 1);
    expect(dashboard.dailyUsage, isEmpty);
    expect(dashboard.recentActivities.single.fileName, 'Không rõ tên ảnh');
    expect(dashboard.recentActivities.single.confidence, 0);
    expect(dashboard.disclaimer, contains('không thay thế'));
  });

  test('M3 dashboard controller exposes loading then data', () async {
    final completer = Completer<UserDashboard>();
    final api = FakeDashboardApi()..onFetch = () => completer.future;
    final container = _container(api);
    await _authenticate(container);

    final future = container.read(dashboardControllerProvider.notifier).load();
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.loading,
    );
    completer.complete(testDashboard());
    await future;

    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.data,
    );
    expect(api.fetchCalls, 1);
  });

  test('M3 dashboard controller exposes empty state', () async {
    final api = FakeDashboardApi();
    final container = _container(api);
    await _authenticate(container);

    await container.read(dashboardControllerProvider.notifier).load();

    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.empty,
    );
  });

  test('M3 dashboard controller exposes safe network error', () async {
    final api = FakeDashboardApi()
      ..onFetch = () async => throw const ApiException(
        code: 'CONNECTION_ERROR',
        message: 'Không kết nối được máy chủ.',
      );
    final container = _container(api);
    await _authenticate(container);

    await container.read(dashboardControllerProvider.notifier).load();

    final state = container.read(dashboardControllerProvider);
    expect(state.status, DashboardStatus.error);
    expect(state.message, 'Không kết nối được máy chủ.');
  });

  test('M3 dashboard retry performs exactly one new request', () async {
    var shouldFail = true;
    final api = FakeDashboardApi()
      ..onFetch = () async {
        if (shouldFail) {
          throw const ApiException(message: 'Lỗi mạng.');
        }
        return testDashboard();
      };
    final container = _container(api);
    await _authenticate(container);
    final controller = container.read(dashboardControllerProvider.notifier);
    await controller.load();
    shouldFail = false;

    await controller.load(force: true);

    expect(api.fetchCalls, 2);
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.data,
    );
  });

  test('M3 refresh keeps old dashboard when request fails', () async {
    var shouldFail = false;
    final api = FakeDashboardApi()
      ..onFetch = () async {
        if (shouldFail) {
          throw const ApiException(message: 'Mất kết nối khi làm mới.');
        }
        return testDashboard();
      };
    final container = _container(api);
    await _authenticate(container);
    final controller = container.read(dashboardControllerProvider.notifier);
    await controller.load();
    shouldFail = true;

    await controller.refresh();

    final state = container.read(dashboardControllerProvider);
    expect(state.status, DashboardStatus.data);
    expect(state.dashboard?.summary.totalInferenceCount, 5);
    expect(state.refreshMessage, 'Mất kết nối khi làm mới.');
  });

  test('M3 dashboard 401 clears authenticated session', () async {
    final store = FakeSessionStore();
    final api = FakeDashboardApi()
      ..onFetch = () async => throw const ApiException(
        statusCode: 401,
        code: 'UNAUTHENTICATED',
        message: 'Phiên đăng nhập đã hết hạn.',
      );
    final container = _container(api, sessionStore: store);
    await _authenticate(container);

    await container.read(dashboardControllerProvider.notifier).load();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(store.clearAllCalls, 1);
  });

  test('M3 dashboard 403 never logs out user', () async {
    final store = FakeSessionStore();
    final api = FakeDashboardApi()
      ..onFetch = () async => throw const ApiException(
        statusCode: 403,
        code: 'ACCESS_DENIED',
        message: 'Bạn không có quyền.',
      );
    final container = _container(api, sessionStore: store);
    await _authenticate(container);

    await container.read(dashboardControllerProvider.notifier).load();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
    expect(store.clearAllCalls, 0);
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.error,
    );
  });

  test('M3 dashboard state resets after logout', () async {
    final api = FakeDashboardApi()..onFetch = () async => testDashboard();
    final container = _container(api);
    await _authenticate(container);
    await container.read(dashboardControllerProvider.notifier).load();

    await container.read(authControllerProvider.notifier).logout();

    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.initial,
    );
    expect(container.read(dashboardControllerProvider).dashboard, isNull);
  });

  test('M3 dashboard source contains no scientific mock metrics', () {
    final source = File(
      'lib/features/dashboard/dashboard_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('mAP')));
    expect(source, isNot(contains('Dice')));
    expect(source, isNot(contains('IoU')));
    expect(source, isNot(contains('accuracy')));
    expect(source, isNot(contains('Dữ liệu minh họa')));
  });

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required Size size,
    required UserDashboard dashboard,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final api = FakeDashboardApi()..onFetch = () async => dashboard;
    final container = _container(api);
    await _authenticate(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: DashboardScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('M3 zero daily usage renders without divide-by-zero', (
    tester,
  ) async {
    final dashboard = UserDashboard(
      summary: const DashboardSummary(totalInferenceCount: 1),
      dailyUsage: List.generate(
        7,
        (index) => DailyUsage(date: DateTime(2026, 7, 25 + index), count: 0),
      ),
      modelUsage: const ModelUsage(),
      predictionUsage: const PredictionUsage(),
      recentActivities: const [],
      disclaimer: emptyDashboard.disclaimer,
    );

    await pumpDashboard(
      tester,
      size: const Size(320, 760),
      dashboard: dashboard,
    );
    await tester.drag(
      find.byKey(const Key('dashboard-data')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hoạt động 7 ngày'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('M3 phone dashboard has no horizontal overflow', (tester) async {
    await pumpDashboard(
      tester,
      size: const Size(320, 760),
      dashboard: testDashboard(),
    );

    expect(find.byKey(const Key('dashboard-data')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('M3 tablet dashboard has no overflow', (tester) async {
    await pumpDashboard(
      tester,
      size: const Size(1000, 900),
      dashboard: testDashboard(),
    );

    expect(find.text('Phân bố họ mô hình'), findsOneWidget);
    expect(find.text('Kết quả dự đoán'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
