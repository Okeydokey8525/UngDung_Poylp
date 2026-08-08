import 'dart:async';
import 'dart:io';

import 'package:app_polyp/app/app_theme.dart';
import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/csrf_interceptor.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/comparison/comparison_api.dart';
import 'package:app_polyp/features/comparison/comparison_controller.dart';
import 'package:app_polyp/features/comparison/comparison_models.dart'
    as comparison_models;
import 'package:app_polyp/features/comparison/comparison_result_screen.dart';
import 'package:app_polyp/features/comparison/comparison_screen.dart';
import 'package:app_polyp/features/comparison/comparison_state.dart';
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/dashboard/dashboard_state.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_api.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ProviderContainer comparisonContainer(
  FakeComparisonApi api, {
  FakeDiagnosisImagePicker? picker,
  FakeSessionStore? sessionStore,
}) {
  final container = ProviderContainer(
    overrides: [
      comparisonApiProvider.overrideWithValue(api),
      diagnosisApiProvider.overrideWithValue(FakeDiagnosisApi()),
      diagnosisImagePickerProvider.overrideWithValue(
        picker ?? FakeDiagnosisImagePicker(),
      ),
      authApiProvider.overrideWithValue(FakeAuthApi()),
      authSessionStoreProvider.overrideWithValue(
        sessionStore ?? FakeSessionStore(),
      ),
      dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> authenticate(ProviderContainer container) => container
    .read(authControllerProvider.notifier)
    .login(const LoginRequest(email: 'an@example.com', password: 'secret-123'));

Widget testApp(
  Widget child,
  FakeComparisonApi comparisonApi, {
  FakeDiagnosisApi? diagnosisApi,
  FakeDiagnosisImagePicker? picker,
}) => ProviderScope(
  overrides: [
    comparisonApiProvider.overrideWithValue(comparisonApi),
    diagnosisApiProvider.overrideWithValue(diagnosisApi ?? FakeDiagnosisApi()),
    diagnosisImagePickerProvider.overrideWithValue(
      picker ?? FakeDiagnosisImagePicker(),
    ),
    authApiProvider.overrideWithValue(FakeAuthApi()),
    authSessionStoreProvider.overrideWithValue(FakeSessionStore()),
    dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  ),
);

ApiException mappedError(int status, String code) => ApiException.fromDio(
  DioException(
    requestOptions: RequestOptions(path: '/api/v1/comparisons'),
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: RequestOptions(path: '/api/v1/comparisons'),
      statusCode: status,
      headers: Headers.fromMap({
        Headers.contentTypeHeader: ['application/json'],
      }),
      data: {'status': status, 'code': code, 'message': 'raw'},
    ),
  ),
);

Future<RequestOptions> captureCreateRequest() async {
  late RequestOptions captured;
  final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
  final adapter = FakeHttpClientAdapter((options) {
    if (options.path.endsWith('/csrf')) {
      return jsonResponse({
        'token': 'csrf-token',
        'headerName': 'X-CSRF-TOKEN',
        'parameterName': '_csrf',
      });
    }
    captured = options;
    return jsonResponse({
      'comparisonGroupId': 'group-1',
      'originalImageUrl': '/original',
      'baseline': {'id': 'b', 'resultImageUrl': '/baseline'},
      'vmamba': {'id': 'v', 'resultImageUrl': '/vmamba'},
    }, statusCode: 201);
  });
  dio.httpClientAdapter = adapter;
  final client = ApiClient(dio);
  final csrf = CsrfController(client);
  dio.interceptors.add(CsrfInterceptor(() => csrf.token));
  await ComparisonApi(client, csrf).createComparison(testSelectedImage());
  return captured;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M5 01 comparison response parses correctly', () {
    final result = comparison_models.ComparisonResult.fromJson({
      'comparisonGroupId': 'g-1',
      'fileName': 'sample.jpg',
      'createdAt': '2026-08-01T10:00:00Z',
      'originalImageUrl': '/original',
      'baseline': {
        'id': 'b',
        'modelType': 'YOLO26n-seg',
        'modelCategory': 'BASELINE',
        'confidence': 0.62,
        'resultImageUrl': '/baseline',
      },
      'vmamba': {
        'id': 'v',
        'modelType': 'YOLO26n-VMamba-seg',
        'modelCategory': 'VMAMBA',
        'confidence': 0.67,
        'resultImageUrl': '/vmamba',
      },
      'totalProcessingTimeMs': 322.7,
      'metadataUrl': '/metadata',
    });
    expect(result.comparisonGroupId, 'g-1');
    expect(result.totalProcessingTimeMs, 322.7);
  });

  test('M5 02 null fields use safe fallbacks', () {
    final result = comparison_models.ComparisonResult.fromJson({
      'baseline': {'confidence': 5, 'maskCount': -1},
      'vmamba': null,
    });
    expect(result.fileName, 'Ảnh nội soi');
    expect(result.baseline.confidence, 1);
    expect(result.baseline.maskCount, 0);
    expect(result.vmamba.processingTimeMs, 0);
  });

  test('M5 03 baseline maps to exact model contract', () {
    expect(testComparisonResult().baseline.modelType, 'YOLO26n-seg');
    expect(testComparisonResult().baseline.modelCategory, 'BASELINE');
  });

  test('M5 04 VMamba maps to exact model contract', () {
    expect(testComparisonResult().vmamba.modelType, 'YOLO26n-VMamba-seg');
    expect(testComparisonResult().vmamba.modelCategory, 'VMAMBA');
  });

  test('M5 05 typed comparison model has no winner property', () {
    final source = File(
      'lib/features/comparison/comparison_models.dart',
    ).readAsStringSync();
    expect(source.toLowerCase(), isNot(contains('winner')));
    expect(source, isNot(contains('betterModel')));
  });

  test('M5 06 submit is disabled without an image', () {
    expect(const ComparisonState().canCompare, isFalse);
  });

  test('M5 07 file over 10 MB is blocked', () {
    expect(
      testSelectedImage(sizeBytes: maxDiagnosisUploadBytes + 1).validationError,
      contains('10 MB'),
    );
  });

  test('M5 08 invalid extension is blocked', () {
    expect(
      testSelectedImage(name: 'image.gif').validationError,
      contains('JPG'),
    );
  });

  testWidgets('M5 09 selected image preview is visible', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      testApp(const ComparisonScreen(), FakeComparisonApi()),
    );
    await tester.tap(find.byKey(const Key('comparison-pick-image')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comparison-image-preview')), findsOneWidget);
    expect(find.text('sample.png'), findsOneWidget);
  });

  test('M5 10 multipart contains only image field', () async {
    final request = await captureCreateRequest();
    final form = request.data! as FormData;
    expect(form.files.single.key, 'image');
    expect(form.fields, isEmpty);
  });

  test('M5 11 multipart never sends modelType', () async {
    final form = (await captureCreateRequest()).data! as FormData;
    expect(form.fields.where((field) => field.key == 'modelType'), isEmpty);
  });

  test('M5 12 multipart sends CSRF header', () async {
    expect(
      (await captureCreateRequest()).headers['X-CSRF-TOKEN'],
      'csrf-token',
    );
  });

  test('M5 13 upload progress updates state', () async {
    final completer = Completer<comparison_models.ComparisonResult>();
    final api = FakeComparisonApi()
      ..onCreate = (_, progress) {
        progress?.call(25, 100);
        return completer.future;
      };
    final container = comparisonContainer(api);
    await container.read(comparisonControllerProvider.notifier).pickImage();
    final pending = container
        .read(comparisonControllerProvider.notifier)
        .compare();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(comparisonControllerProvider).uploadProgress, 0.25);
    completer.complete(testComparisonResult());
    await pending;
  });

  test('M5 14 completed upload changes to honest processing state', () async {
    final completer = Completer<comparison_models.ComparisonResult>();
    final api = FakeComparisonApi()
      ..onCreate = (_, progress) {
        progress?.call(1, 1);
        return completer.future;
      };
    final container = comparisonContainer(api);
    await container.read(comparisonControllerProvider.notifier).pickImage();
    final pending = container
        .read(comparisonControllerProvider.notifier)
        .compare();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(comparisonControllerProvider).status,
      ComparisonStatus.processing,
    );
    completer.complete(testComparisonResult());
    await pending;
  });

  test('M5 15 UI contains no fabricated inference percentage', () {
    final source = File(
      'lib/features/comparison/comparison_screen.dart',
    ).readAsStringSync();
    expect(source, contains('chạy lần lượt Baseline và VMamba'));
    expect(source, isNot(contains('inferenceProgress')));
  });

  test('M5 16 create success stores comparison result', () async {
    final container = comparisonContainer(FakeComparisonApi());
    await container.read(comparisonControllerProvider.notifier).pickImage();
    final result = await container
        .read(comparisonControllerProvider.notifier)
        .compare();
    expect(result?.comparisonGroupId, 'comparison-group-1');
    expect(
      container.read(comparisonControllerProvider).status,
      ComparisonStatus.success,
    );
  });

  test('M5 17 create failure is not automatically retried', () async {
    final api = FakeComparisonApi()
      ..onCreate = (_, _) async =>
          throw mappedError(503, 'AI_SERVICE_UNAVAILABLE');
    final container = comparisonContainer(api);
    await container.read(comparisonControllerProvider.notifier).pickImage();
    await container.read(comparisonControllerProvider.notifier).compare();
    expect(api.createCalls, 1);
  });

  test('M5 18 double submit is blocked', () async {
    final completer = Completer<comparison_models.ComparisonResult>();
    final api = FakeComparisonApi()..onCreate = (_, _) => completer.future;
    final container = comparisonContainer(api);
    await container.read(comparisonControllerProvider.notifier).pickImage();
    final first = container
        .read(comparisonControllerProvider.notifier)
        .compare();
    expect(
      await container.read(comparisonControllerProvider.notifier).compare(),
      isNull,
    );
    expect(api.createCalls, 1);
    completer.complete(testComparisonResult());
    await first;
  });

  for (final item in [
    (19, 413, 'FILE_TOO_LARGE', '10 MB'),
    (20, 415, 'UNSUPPORTED_MEDIA_TYPE', 'JPG'),
    (21, 422, 'INVALID_IMAGE', 'hợp lệ'),
    (22, 503, 'VMAMBA_MODEL_UNAVAILABLE', 'VMamba'),
    (23, 504, 'VMAMBA_TIMEOUT', 'quá thời gian'),
  ]) {
    test('M5 ${item.$1} maps ${item.$3} to friendly message', () async {
      final api = FakeComparisonApi()
        ..onCreate = (_, _) async => throw mappedError(item.$2, item.$3);
      final container = comparisonContainer(api);
      await container.read(comparisonControllerProvider.notifier).pickImage();
      await container.read(comparisonControllerProvider.notifier).compare();
      expect(
        container.read(comparisonControllerProvider).message,
        contains(item.$4),
      );
    });
  }

  test('M5 24 comparison 401 logs out', () async {
    final session = FakeSessionStore();
    final api = FakeComparisonApi()
      ..onCreate = (_, _) async => throw mappedError(401, 'UNAUTHENTICATED');
    final container = comparisonContainer(api, sessionStore: session);
    await authenticate(container);
    await container.read(comparisonControllerProvider.notifier).pickImage();
    await container.read(comparisonControllerProvider.notifier).compare();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(session.clearAllCalls, greaterThan(0));
  });

  test('M5 25 comparison 403 does not log out', () async {
    final api = FakeComparisonApi()
      ..onCreate = (_, _) async => throw mappedError(403, 'ACCESS_DENIED');
    final container = comparisonContainer(api);
    await authenticate(container);
    await container.read(comparisonControllerProvider.notifier).pickImage();
    await container.read(comparisonControllerProvider.notifier).compare();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
  });

  testWidgets('M5 26 phone result uses Baseline and VMamba tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comparison-phone-tabs')), findsOneWidget);
    expect(find.text('Baseline'), findsWidgets);
    expect(find.text('VMamba'), findsWidgets);
  });

  testWidgets('M5 27 wide tablet result uses split view', (tester) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comparison-tablet-split')), findsOneWidget);
  });

  testWidgets('M5 28 original authenticated image is built exactly once', (
    tester,
  ) async {
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('comparison-original-image')), findsOneWidget);
  });

  testWidgets('M5 29 baseline overlay uses its API URL', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('baseline-overlay-image')), findsOneWidget);
  });

  testWidgets('M5 30 VMamba overlay uses its API URL', (tester) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vmamba-overlay-image')), findsOneWidget);
  });

  testWidgets('M5 31 both model metadata values are displayed', (tester) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confidence: 62.0%'), findsOneWidget);
    expect(find.text('Confidence: 67.0%'), findsOneWidget);
    expect(find.text('Số mask: 3'), findsOneWidget);
  });

  testWidgets('M5 32 total sequential time is displayed', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('322.7 ms'), findsOneWidget);
  });

  test('M5 33 result source contains no model tốt hơn claim', () {
    expect(
      File(
        'lib/features/comparison/comparison_result_screen.dart',
      ).readAsStringSync(),
      isNot(contains('model tốt hơn')),
    );
  });

  test('M5 34 result source contains no winner field', () {
    expect(
      File(
        'lib/features/comparison/comparison_result_screen.dart',
      ).readAsStringSync().toLowerCase(),
      isNot(contains('winner')),
    );
  });

  testWidgets('M5 35 comparison result has research disclaimer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('comparison-result-disclaimer')),
      findsOneWidget,
    );
  });

  for (final item in [
    (36, 'comparison-original-fullscreen'),
    (37, 'baseline-fullscreen'),
    (38, 'vmamba-fullscreen'),
  ]) {
    test('M5 ${item.$1} fullscreen action is wired for ${item.$2}', () {
      final source = File(
        'lib/features/comparison/comparison_result_screen.dart',
      ).readAsStringSync();
      if (item.$1 == 36) {
        expect(source, contains("Key('${item.$2}')"));
      } else {
        expect(source, contains("Key('\$keyPrefix-fullscreen')"));
      }
      expect(source, contains('AuthenticatedImageArguments'));
    });
  }

  testWidgets('M5 39 delete requires explicit group confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final result = testComparisonResult();
    await tester.pumpWidget(
      testApp(
        ComparisonResultScreen(
          comparisonGroupId: result.comparisonGroupId,
          initialResult: result,
        ),
        FakeComparisonApi(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-comparison-button')));
    await tester.pumpAndSettle();
    expect(find.text('Xóa phiên so sánh?'), findsOneWidget);
    expect(find.byKey(const Key('confirm-delete-comparison')), findsOneWidget);
  });

  test('M5 40 delete calls comparison group endpoint', () async {
    late RequestOptions captured;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter((options) {
      if (options.path.endsWith('/csrf')) {
        return jsonResponse({
          'token': 'x',
          'headerName': 'X-CSRF-TOKEN',
          'parameterName': '_csrf',
        });
      }
      captured = options;
      return ResponseBody.fromBytes(const [], 204);
    });
    dio.httpClientAdapter = adapter;
    final client = ApiClient(dio);
    final csrf = CsrfController(client);
    dio.interceptors.add(CsrfInterceptor(() => csrf.token));
    await ComparisonApi(client, csrf).deleteComparison('group-1');
    expect(captured.path, '/api/v1/comparisons/group-1');
    expect(captured.method, 'DELETE');
  });

  test('M5 41 group delete never calls two diagnosis deletes', () async {
    final api = FakeComparisonApi();
    final container = comparisonContainer(api);
    await container
        .read(comparisonControllerProvider.notifier)
        .openResult(
          'comparison-group-1',
          initialResult: testComparisonResult(),
        );
    await container.read(comparisonControllerProvider.notifier).deleteCurrent();
    expect(api.deleteCalls, 1);
    expect(api.lastDeletedGroupId, 'comparison-group-1');
  });

  test('M5 42 delete success invalidates dashboard', () async {
    final api = FakeComparisonApi();
    final container = comparisonContainer(api);
    await container.read(dashboardControllerProvider.notifier).load();
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.empty,
    );
    await container
        .read(comparisonControllerProvider.notifier)
        .openResult(
          'comparison-group-1',
          initialResult: testComparisonResult(),
        );
    await container.read(comparisonControllerProvider.notifier).deleteCurrent();
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.initial,
    );
  });

  test('M5 43 delete failure keeps result visible', () async {
    final api = FakeComparisonApi()
      ..onDelete = (_) async =>
          throw mappedError(503, 'AI_SERVICE_UNAVAILABLE');
    final container = comparisonContainer(api);
    await container
        .read(comparisonControllerProvider.notifier)
        .openResult(
          'comparison-group-1',
          initialResult: testComparisonResult(),
        );
    expect(
      await container
          .read(comparisonControllerProvider.notifier)
          .deleteCurrent(),
      isFalse,
    );
    expect(container.read(comparisonControllerProvider).result, isNotNull);
  });

  test('M5 44 direct result route loads group by ID', () async {
    final api = FakeComparisonApi();
    final container = comparisonContainer(api);
    await container
        .read(comparisonControllerProvider.notifier)
        .openResult('deep-group');
    expect(api.getCalls, 1);
    expect(
      container.read(comparisonControllerProvider).result?.comparisonGroupId,
      'deep-group',
    );
  });

  testWidgets('M5 45 missing group renders safe error state', (tester) async {
    final api = FakeComparisonApi()
      ..onGet = (_) async => throw mappedError(404, 'RESOURCE_NOT_FOUND');
    await tester.pumpWidget(
      testApp(const ComparisonResultScreen(comparisonGroupId: 'missing'), api),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải phiên so sánh'), findsOneWidget);
    expect(find.textContaining('Không tìm thấy'), findsOneWidget);
  });

  test('M5 46 dashboard comparison activity opens real result route', () {
    final source = File(
      'lib/features/dashboard/dashboard_screen.dart',
    ).readAsStringSync();
    expect(source, contains('comparisonResult(activity.comparisonGroupId!)'));
  });

  testWidgets('M5 47 phone 320 comparison screen has no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      testApp(const ComparisonScreen(), FakeComparisonApi()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('M5 48 tablet comparison screen has no overflow', (tester) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      testApp(const ComparisonScreen(), FakeComparisonApi()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('M5 49 diagnosis M4 implementation remains real', () {
    final source = File(
      'lib/features/diagnosis/diagnosis_api.dart',
    ).readAsStringSync();
    expect(source, contains('/api/v1/diagnoses'));
    expect(source, contains('modelType'));
  });

  test('M5 50 auth dashboard and profile features remain present', () {
    expect(File('lib/features/auth/auth_controller.dart').existsSync(), isTrue);
    expect(
      File('lib/features/dashboard/dashboard_controller.dart').existsSync(),
      isTrue,
    );
    expect(
      File('lib/features/account/account_controller.dart').existsSync(),
      isTrue,
    );
  });

  test('M5 51 comparison feature contains no legacy mock text or data', () {
    final source = Directory('lib/features/comparison')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join();
    expect(source.toLowerCase(), isNot(contains('kết quả so sánh mock')));
    expect(source, isNot(contains('M1 chưa')));
    expect(source, isNot(contains('84,7%')));
  });
}
