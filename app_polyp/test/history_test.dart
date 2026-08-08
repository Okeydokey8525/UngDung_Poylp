import 'dart:io';

import 'package:app_polyp/app/app_theme.dart';
import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/dashboard/dashboard_state.dart';
import 'package:app_polyp/features/history/history_api.dart';
import 'package:app_polyp/features/history/history_controller.dart';
import 'package:app_polyp/features/history/history_filters.dart';
import 'package:app_polyp/features/history/history_models.dart';
import 'package:app_polyp/features/history/history_screen.dart';
import 'package:app_polyp/features/history/history_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

PagedResponse<DiagnosisHistoryItem> diagnosisPage(
  List<DiagnosisHistoryItem> items, {
  int page = 0,
  int totalPages = 1,
  int? totalItems,
  bool hasNext = false,
}) => PagedResponse(
  items: items,
  page: page,
  size: 10,
  totalItems: totalItems ?? items.length,
  totalPages: totalPages,
  hasNext: hasNext,
  hasPrevious: page > 0,
);

PagedResponse<ComparisonHistoryItem> comparisonPage(
  List<ComparisonHistoryItem> items, {
  int page = 0,
  int totalPages = 1,
  int? totalItems,
  bool hasNext = false,
}) => PagedResponse(
  items: items,
  page: page,
  size: 10,
  totalItems: totalItems ?? items.length,
  totalPages: totalPages,
  hasNext: hasNext,
  hasPrevious: page > 0,
);

ProviderContainer historyContainer(
  FakeHistoryApi api, {
  FakeAuthApi? authApi,
  FakeSessionStore? sessionStore,
  FakeDashboardApi? dashboardApi,
}) {
  final container = ProviderContainer(
    overrides: [
      historyApiProvider.overrideWithValue(api),
      authApiProvider.overrideWithValue(authApi ?? FakeAuthApi()),
      authSessionStoreProvider.overrideWithValue(
        sessionStore ?? FakeSessionStore(),
      ),
      dashboardApiProvider.overrideWithValue(
        dashboardApi ?? FakeDashboardApi(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> authenticate(ProviderContainer container) => container
    .read(authControllerProvider.notifier)
    .login(const LoginRequest(email: 'an@example.com', password: 'secret-123'));

Widget historyApp(FakeHistoryApi api, {GoRouter? router}) {
  final child = router == null
      ? MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: HistoryScreen()),
        )
      : MaterialApp.router(theme: AppTheme.light, routerConfig: router);
  return ProviderScope(
    overrides: [
      historyApiProvider.overrideWithValue(api),
      authApiProvider.overrideWithValue(FakeAuthApi()),
      authSessionStoreProvider.overrideWithValue(FakeSessionStore()),
      dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
    ],
    child: child,
  );
}

ApiException apiError(int status, String code, String message) =>
    ApiException(statusCode: status, code: code, message: message);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M6 01 paged diagnosis response parses correctly', () {
    final page = PagedResponse.fromJson({
      'items': [
        {
          'id': 'd-1',
          'fileName': 'sample.jpg',
          'modelType': 'YOLO26n-seg',
          'modelCategory': 'BASELINE',
          'detected': true,
          'confidence': 0.62,
          'maskCount': 2,
          'processingTimeMs': 148.5,
          'createdAt': '2026-08-01T08:00:00Z',
        },
      ],
      'page': 1,
      'size': 10,
      'totalItems': 11,
      'totalPages': 2,
      'hasNext': false,
      'hasPrevious': true,
    }, DiagnosisHistoryItem.fromJson);
    expect(page.items.single.id, 'd-1');
    expect(page.page, 1);
    expect(page.totalItems, 11);
    expect(page.hasPrevious, isTrue);
  });

  test('M6 02 paged comparison response parses correctly', () {
    final page = PagedResponse.fromJson({
      'items': [
        {
          'comparisonGroupId': 'g-1',
          'fileName': 'scope.png',
          'createdAt': '2026-08-01T08:00:00Z',
          'baseline': {'id': 'b', 'confidence': 0.5},
          'vmamba': {'id': 'v', 'confidence': 0.6},
          'totalProcessingTimeMs': 300,
        },
      ],
      'page': 0,
      'size': 10,
      'totalItems': 1,
      'totalPages': 1,
      'hasNext': false,
      'hasPrevious': false,
    }, ComparisonHistoryItem.fromJson);
    expect(page.items.single.comparisonGroupId, 'g-1');
    expect(page.items.single.vmamba.confidence, 0.6);
    expect(page.totalPages, 1);
  });

  test('M6 03 null fields use safe fallbacks', () {
    final diagnosis = DiagnosisHistoryItem.fromJson({
      'confidence': 9,
      'maskCount': -1,
      'processingTimeMs': -4,
    });
    final comparison = ComparisonHistoryItem.fromJson({});
    expect(diagnosis.fileName, isNotEmpty);
    expect(diagnosis.confidence, 1);
    expect(diagnosis.maskCount, 0);
    expect(diagnosis.createdAt, isNull);
    expect(comparison.baseline.id, isEmpty);
  });

  test('M6 04 diagnosis page loads real repository data', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    expect(
      container.read(diagnosisHistoryControllerProvider).items,
      hasLength(1),
    );
    expect(api.lastDiagnosisPage, 0);
  });

  test('M6 05 comparison page loads real repository data', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container.read(comparisonHistoryControllerProvider.notifier).load();
    expect(
      container.read(comparisonHistoryControllerProvider).items,
      hasLength(1),
    );
    expect(api.lastComparisonPage, 0);
  });

  test('M6 06 diagnosis empty response uses empty state', () async {
    final api = FakeHistoryApi()
      ..onDiagnoses = (_, _) async => diagnosisPage([]);
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    expect(
      container.read(diagnosisHistoryControllerProvider).status,
      HistoryStatus.empty,
    );
  });

  test('M6 07 comparison empty response uses empty state', () async {
    final api = FakeHistoryApi()
      ..onComparisons = (_, _) async => comparisonPage([]);
    final container = historyContainer(api);
    await container.read(comparisonHistoryControllerProvider.notifier).load();
    expect(
      container.read(comparisonHistoryControllerProvider).status,
      HistoryStatus.empty,
    );
  });

  test('M6 08 diagnosis error can be retried', () async {
    final api = FakeHistoryApi()
      ..onDiagnoses = (_, _) async => throw apiError(503, 'DOWN', 'Thử lại');
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    expect(
      container.read(diagnosisHistoryControllerProvider).status,
      HistoryStatus.error,
    );
    api.onDiagnoses = (_, _) async =>
        diagnosisPage([testDiagnosisHistoryItem()]);
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .load(force: true);
    expect(
      container.read(diagnosisHistoryControllerProvider).status,
      HistoryStatus.data,
    );
  });

  test('M6 09 comparison error can be retried', () async {
    final api = FakeHistoryApi()
      ..onComparisons = (_, _) async => throw apiError(503, 'DOWN', 'Thử lại');
    final container = historyContainer(api);
    await container.read(comparisonHistoryControllerProvider.notifier).load();
    expect(
      container.read(comparisonHistoryControllerProvider).status,
      HistoryStatus.error,
    );
    api.onComparisons = (_, _) async =>
        comparisonPage([testComparisonHistoryItem()]);
    await container
        .read(comparisonHistoryControllerProvider.notifier)
        .load(force: true);
    expect(
      container.read(comparisonHistoryControllerProvider).status,
      HistoryStatus.data,
    );
  });

  test('M6 10 each tab keeps independent state', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .search('diagnosis');
    await container
        .read(comparisonHistoryControllerProvider.notifier)
        .search('comparison');
    expect(
      container.read(diagnosisHistoryControllerProvider).filter.keyword,
      'diagnosis',
    );
    expect(
      container.read(comparisonHistoryControllerProvider).filter.keyword,
      'comparison',
    );
  });

  test('M6 11 refresh preserves the active filter', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    const filter = DiagnosisHistoryFilter(model: 'YOLO26n-seg', sort: 'oldest');
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .applyFilter(filter);
    await container.read(diagnosisHistoryControllerProvider.notifier).refresh();
    expect(api.lastDiagnosisFilter?.model, 'YOLO26n-seg');
    expect(api.lastDiagnosisFilter?.sort, 'oldest');
    expect(api.lastDiagnosisPage, 0);
  });

  test('M6 12 load more appends the next page', () async {
    final api = FakeHistoryApi()
      ..onDiagnoses = (_, page) async => page == 0
          ? diagnosisPage(
              [testDiagnosisHistoryItem(id: 'd-1')],
              totalPages: 2,
              totalItems: 2,
              hasNext: true,
            )
          : diagnosisPage(
              [testDiagnosisHistoryItem(id: 'd-2')],
              page: 1,
              totalPages: 2,
              totalItems: 2,
            );
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .loadMore();
    expect(
      container.read(diagnosisHistoryControllerProvider).items.map((e) => e.id),
      ['d-1', 'd-2'],
    );
  });

  test('M6 13 load more removes duplicate ids', () async {
    final api = FakeHistoryApi()
      ..onDiagnoses = (_, page) async => page == 0
          ? diagnosisPage(
              [testDiagnosisHistoryItem(id: 'same')],
              totalPages: 2,
              totalItems: 1,
              hasNext: true,
            )
          : diagnosisPage(
              [testDiagnosisHistoryItem(id: 'same')],
              page: 1,
              totalPages: 2,
              totalItems: 1,
            );
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .loadMore();
    expect(
      container.read(diagnosisHistoryControllerProvider).items,
      hasLength(1),
    );
  });

  test('M6 14 hasNext false prevents another request', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .loadMore();
    expect(api.diagnosisCalls, 1);
  });

  test('M6 15 search trims whitespace', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .search('  sample.jpg  ');
    expect(api.lastDiagnosisFilter?.keyword, 'sample.jpg');
  });

  test('M6 16 search is limited to 100 characters', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .search('x' * 140);
    expect(api.lastDiagnosisFilter?.keyword, hasLength(100));
  });

  test('M6 17 clear search keeps other filters', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .applyFilter(
          const DiagnosisHistoryFilter(keyword: 'scope', detected: 'true'),
        );
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .clearSearch();
    expect(api.lastDiagnosisFilter?.keyword, isEmpty);
    expect(api.lastDiagnosisFilter?.detected, 'true');
  });

  test('M6 18 diagnosis filter applies all supported fields', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    final filter = DiagnosisHistoryFilter(
      model: 'YOLO26n-VMamba-seg',
      detected: 'false',
      dateFrom: DateTime(2026, 7, 1),
      dateTo: DateTime(2026, 7, 31),
      sort: 'processing-desc',
      size: 20,
    );
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .applyFilter(filter);
    expect(api.lastDiagnosisFilter, same(filter));
  });

  test('M6 19 comparison filter applies all supported fields', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    final filter = ComparisonHistoryFilter(
      baselineDetected: 'true',
      vmambaDetected: 'false',
      dateFrom: DateTime(2026, 7, 1),
      dateTo: DateTime(2026, 7, 31),
      sort: 'total-processing-asc',
      size: 50,
    );
    await container
        .read(comparisonHistoryControllerProvider.notifier)
        .applyFilter(filter);
    expect(api.lastComparisonFilter, same(filter));
  });

  test('M6 20 reset affects only the selected controller', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .search('d');
    await container
        .read(comparisonHistoryControllerProvider.notifier)
        .search('c');
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .resetFilter();
    expect(
      container.read(diagnosisHistoryControllerProvider).filter.keyword,
      isEmpty,
    );
    expect(
      container.read(comparisonHistoryControllerProvider).filter.keyword,
      'c',
    );
  });

  test('M6 21 invalid date range is blocked before API call', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .applyFilter(
          DiagnosisHistoryFilter(
            dateFrom: DateTime(2026, 8, 2),
            dateTo: DateTime(2026, 8, 1),
          ),
        );
    expect(api.diagnosisCalls, 0);
    expect(
      container.read(diagnosisHistoryControllerProvider).status,
      HistoryStatus.idle,
    );
  });

  test('M6 22 draft filter does not call API before Apply', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    const draft = ComparisonHistoryFilter(vmambaDetected: 'true');
    expect(draft.activeCount, 1);
    expect(api.comparisonCalls, 0);
    await container
        .read(comparisonHistoryControllerProvider.notifier)
        .applyFilter(draft);
    expect(api.comparisonCalls, 1);
  });

  test('M6 23 history 401 clears authenticated session', () async {
    final session = FakeSessionStore();
    final api = FakeHistoryApi()
      ..onDiagnoses = (_, _) async =>
          throw apiError(401, 'UNAUTHENTICATED', 'Hết hạn');
    final container = historyContainer(api, sessionStore: session);
    await authenticate(container);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(session.clearAllCalls, greaterThan(0));
  });

  test('M6 24 history 403 does not log the user out', () async {
    final api = FakeHistoryApi()
      ..onDiagnoses = (_, _) async =>
          throw apiError(403, 'ACCESS_DENIED', 'Không có quyền');
    final container = historyContainer(api);
    await authenticate(container);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
  });

  testWidgets('M6 25 diagnosis item opens the diagnosis result route', (
    tester,
  ) async {
    final api = FakeHistoryApi();
    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(
          path: '/history',
          builder: (_, _) => const Scaffold(body: HistoryScreen()),
        ),
        GoRoute(
          path: '/diagnosis/result/:id',
          builder: (_, state) =>
              Text('diagnosis:${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/comparison/result/:id',
          builder: (_, state) =>
              Text('comparison:${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(historyApp(api, router: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sample.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('diagnosis:diagnosis-1'), findsOneWidget);
  });

  testWidgets('M6 26 comparison item opens the comparison result route', (
    tester,
  ) async {
    final api = FakeHistoryApi();
    final router = GoRouter(
      initialLocation: '/history',
      routes: [
        GoRoute(
          path: '/history',
          builder: (_, _) => const Scaffold(body: HistoryScreen()),
        ),
        GoRoute(
          path: '/diagnosis/result/:id',
          builder: (_, state) =>
              Text('diagnosis:${state.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/comparison/result/:id',
          builder: (_, state) =>
              Text('comparison:${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(historyApp(api, router: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('So sánh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sample.png'));
    await tester.pumpAndSettle();
    expect(find.text('comparison:comparison-group-1'), findsOneWidget);
  });

  testWidgets('M6 27 diagnosis delete requires confirmation', (tester) async {
    await tester.pumpWidget(historyApp(FakeHistoryApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-diagnosis-diagnosis-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-delete-confirm')), findsOneWidget);
  });

  testWidgets('M6 28 comparison delete requires confirmation', (tester) async {
    await tester.pumpWidget(historyApp(FakeHistoryApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('So sánh'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('delete-comparison-comparison-group-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-delete-confirm')), findsOneWidget);
  });

  test('M6 29 diagnosis delete sends the item id', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    expect(
      await container
          .read(diagnosisHistoryControllerProvider.notifier)
          .deleteItem('diagnosis-1'),
      isTrue,
    );
    expect(api.lastDeletedDiagnosisId, 'diagnosis-1');
  });

  test('M6 30 comparison delete sends the group id', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container.read(comparisonHistoryControllerProvider.notifier).load();
    expect(
      await container
          .read(comparisonHistoryControllerProvider.notifier)
          .deleteItem('comparison-group-1'),
      isTrue,
    );
    expect(api.lastDeletedComparisonId, 'comparison-group-1');
  });

  test('M6 31 successful delete removes the local item', () async {
    final api = FakeHistoryApi();
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .deleteItem('diagnosis-1');
    expect(container.read(diagnosisHistoryControllerProvider).items, isEmpty);
    expect(container.read(diagnosisHistoryControllerProvider).totalItems, 0);
  });

  test('M6 32 successful delete invalidates dashboard', () async {
    final api = FakeHistoryApi();
    final dashboard = FakeDashboardApi();
    final container = historyContainer(api, dashboardApi: dashboard);
    await container.read(dashboardControllerProvider.notifier).load();
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.empty,
    );
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .deleteItem('diagnosis-1');
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.initial,
    );
  });

  test(
    'M6 33 deleting the final item on a page loads the previous page',
    () async {
      var calls = 0;
      final api = FakeHistoryApi()
        ..onDiagnoses = (_, _) async => calls++ == 0
            ? diagnosisPage(
                [testDiagnosisHistoryItem(id: 'last')],
                page: 1,
                totalPages: 2,
                totalItems: 2,
              )
            : diagnosisPage([testDiagnosisHistoryItem(id: 'previous')]);
      final container = historyContainer(api);
      await container.read(diagnosisHistoryControllerProvider.notifier).load();
      await container
          .read(diagnosisHistoryControllerProvider.notifier)
          .deleteItem('last');
      expect(api.lastDiagnosisPage, 0);
      expect(
        container.read(diagnosisHistoryControllerProvider).items.single.id,
        'previous',
      );
    },
  );

  test('M6 34 failed delete preserves the item', () async {
    final api = FakeHistoryApi()
      ..onDeleteDiagnosis = (_) async => throw apiError(503, 'DOWN', 'Thử lại');
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    expect(
      await container
          .read(diagnosisHistoryControllerProvider.notifier)
          .deleteItem('diagnosis-1'),
      isFalse,
    );
    expect(
      container.read(diagnosisHistoryControllerProvider).items.single.id,
      'diagnosis-1',
    );
  });

  testWidgets('M6 35 phone width 320 has no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(historyApp(FakeHistoryApi()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('M6 36 tablet layout has no overflow', (tester) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(historyApp(FakeHistoryApi()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('M6 37 history contains no mock screen or mock data', () {
    final source = Directory('lib/features/history')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join();
    expect(source.toLowerCase(), isNot(contains('history mock')));
    expect(source.toLowerCase(), isNot(contains('lịch sử mock')));
    expect(
      File('lib/features/history/history_detail_screen.dart').existsSync(),
      isFalse,
    );
  });

  test('M6 38 M4 and M5 result routes remain wired', () {
    final source = File('lib/navigation/app_router.dart').readAsStringSync();
    expect(source, contains("path: 'result/:id'"));
    expect(source, contains("path: 'result/:comparisonGroupId'"));
    expect(
      File('lib/features/diagnosis/diagnosis_result_screen.dart').existsSync(),
      isTrue,
    );
    expect(
      File(
        'lib/features/comparison/comparison_result_screen.dart',
      ).existsSync(),
      isTrue,
    );
  });

  test('M6 39 auth dashboard and profile features remain present', () {
    expect(File('lib/features/auth/auth_controller.dart').existsSync(), isTrue);
    expect(
      File('lib/features/dashboard/dashboard_controller.dart').existsSync(),
      isTrue,
    );
    expect(
      File('lib/features/account/edit_profile_screen.dart').existsSync(),
      isTrue,
    );
  });

  test('M6 40 filter query parameters are URL encoded correctly', () async {
    late RequestOptions request;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    dio.httpClientAdapter = FakeHttpClientAdapter((options) {
      request = options;
      return jsonResponse({
        'items': [],
        'page': 0,
        'size': 20,
        'totalItems': 0,
        'totalPages': 0,
        'hasNext': false,
        'hasPrevious': false,
      });
    });
    final client = ApiClient(dio);
    await HistoryApi(client, CsrfController(client)).getDiagnoses(
      DiagnosisHistoryFilter(
        keyword: 'scope & polyp',
        model: 'YOLO26n-VMamba-seg',
        dateFrom: DateTime(2026, 8, 1),
        sort: 'confidence-desc',
        size: 20,
      ),
      2,
    );
    final uri = Uri.parse(request.path);
    expect(uri.path, '/api/v1/diagnoses');
    expect(uri.query, contains('keyword=scope+%26+polyp'));
    expect(uri.queryParameters['keyword'], 'scope & polyp');
    expect(uri.queryParameters['model'], 'YOLO26n-VMamba-seg');
    expect(uri.queryParameters['dateFrom'], '2026-08-01');
    expect(uri.queryParameters['page'], '2');
  });

  test('M6 41 diagnosis delete 404 refreshes the list', () async {
    var loads = 0;
    final api = FakeHistoryApi()
      ..onDiagnoses = ((_, _) async => loads++ == 0
          ? diagnosisPage([testDiagnosisHistoryItem()])
          : diagnosisPage([]))
      ..onDeleteDiagnosis = (_) async =>
          throw apiError(404, 'RESOURCE_NOT_FOUND', 'Đã bị xóa');
    final container = historyContainer(api);
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    await container
        .read(diagnosisHistoryControllerProvider.notifier)
        .deleteItem('diagnosis-1');
    expect(api.diagnosisCalls, 2);
    expect(container.read(diagnosisHistoryControllerProvider).items, isEmpty);
  });

  test('M6 42 comparison delete 404 refreshes the list', () async {
    var loads = 0;
    final api = FakeHistoryApi()
      ..onComparisons = ((_, _) async => loads++ == 0
          ? comparisonPage([testComparisonHistoryItem()])
          : comparisonPage([]))
      ..onDeleteComparison = (_) async =>
          throw apiError(404, 'RESOURCE_NOT_FOUND', 'Đã bị xóa');
    final container = historyContainer(api);
    await container.read(comparisonHistoryControllerProvider.notifier).load();
    await container
        .read(comparisonHistoryControllerProvider.notifier)
        .deleteItem('comparison-group-1');
    expect(api.comparisonCalls, 2);
    expect(container.read(comparisonHistoryControllerProvider).items, isEmpty);
  });
}
