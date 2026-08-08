import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/dashboard/dashboard_state.dart';
import 'package:app_polyp/features/diagnosis/authenticated_image.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_api.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_result_screen.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_screen.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_state.dart';
import 'package:app_polyp/features/diagnosis/fullscreen_image_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ProviderContainer diagnosisContainer(
  FakeDiagnosisApi api, {
  FakeDiagnosisImagePicker? picker,
  FakeAuthApi? authApi,
  FakeSessionStore? sessionStore,
}) {
  final container = ProviderContainer(
    overrides: [
      diagnosisApiProvider.overrideWithValue(api),
      diagnosisImagePickerProvider.overrideWithValue(
        picker ?? FakeDiagnosisImagePicker(),
      ),
      authApiProvider.overrideWithValue(authApi ?? FakeAuthApi()),
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
  FakeDiagnosisApi api, {
  FakeDiagnosisImagePicker? picker,
  FakeSessionStore? sessionStore,
}) => ProviderScope(
  overrides: [
    diagnosisApiProvider.overrideWithValue(api),
    diagnosisImagePickerProvider.overrideWithValue(
      picker ?? FakeDiagnosisImagePicker(),
    ),
    authApiProvider.overrideWithValue(FakeAuthApi()),
    authSessionStoreProvider.overrideWithValue(
      sessionStore ?? FakeSessionStore(),
    ),
    dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
  ],
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  ),
);

ApiException apiError(int status, String code, String message) =>
    ApiException(statusCode: status, code: code, message: message);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M4 01 diagnosis response parses typed fields', () {
    final result = DiagnosisResult.fromJson({
      'id': 'd-1',
      'fileName': 'sample.jpg',
      'modelType': 'YOLO26n-seg',
      'modelCategory': 'BASELINE',
      'detected': true,
      'label': 'polyp',
      'confidence': 0.62,
      'maskCount': 2,
      'processingTimeMs': 148.5,
      'createdAt': '2026-08-01T08:00:00Z',
      'originalImageUrl': '/original',
      'resultImageUrl': '/result',
      'metadataUrl': '/metadata',
    });
    expect(result.id, 'd-1');
    expect(result.confidence, 0.62);
    expect(result.maskCount, 2);
  });

  test('M4 02 diagnosis null fields use safe fallbacks', () {
    final result = DiagnosisResult.fromJson({
      'confidence': 9,
      'maskCount': -2,
      'processingTimeMs': null,
    });
    expect(result.fileName, 'Ảnh nội soi');
    expect(result.confidence, 1);
    expect(result.maskCount, 0);
    expect(result.label, isNull);
  });

  test('M4 03 baseline model contract is exact', () {
    expect(DiagnosisModelOption.baseline.apiValue, 'YOLO26n-seg');
    expect(DiagnosisModelOption.baseline.category, 'Baseline');
  });

  test('M4 04 VMamba model contract is exact', () {
    expect(DiagnosisModelOption.vmamba.apiValue, 'YOLO26n-VMamba-seg');
    expect(DiagnosisModelOption.values, hasLength(2));
  });

  test('M4 05 file over 10 MB is blocked by client', () {
    expect(
      testSelectedImage(sizeBytes: maxDiagnosisUploadBytes + 1).validationError,
      contains('10 MB'),
    );
  });

  test('M4 06 invalid extension is blocked by client', () {
    expect(
      testSelectedImage(name: 'sample.gif').validationError,
      contains('JPG'),
    );
  });

  test('M4 07 MIME and extension mismatch is blocked', () {
    expect(
      testSelectedImage(
        name: 'sample.png',
        mimeType: 'image/jpeg',
      ).validationError,
      contains('không khớp'),
    );
  });

  test('M4 08 empty image is blocked by client', () {
    expect(testSelectedImage(sizeBytes: 0).validationError, contains('rỗng'));
  });

  test('M4 09 submit is disabled without selected image', () {
    expect(const DiagnosisState().canAnalyze, isFalse);
  });

  test('M4 10 valid selected image enables submit', () {
    expect(
      DiagnosisState(selectedImage: testSelectedImage()).canAnalyze,
      isTrue,
    );
  });

  test('M4 11 picker selection is stored for preview', () async {
    final container = diagnosisContainer(FakeDiagnosisApi());
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    final state = container.read(diagnosisControllerProvider);
    expect(state.status, DiagnosisStatus.selected);
    expect(state.selectedImage?.name, 'sample.png');
  });

  test('M4 12 controller selects Baseline', () {
    final container = diagnosisContainer(FakeDiagnosisApi());
    container
        .read(diagnosisControllerProvider.notifier)
        .selectModel(DiagnosisModelOption.baseline);
    expect(
      container.read(diagnosisControllerProvider).selectedModel,
      DiagnosisModelOption.baseline,
    );
  });

  test('M4 13 controller selects VMamba', () {
    final container = diagnosisContainer(FakeDiagnosisApi());
    container
        .read(diagnosisControllerProvider.notifier)
        .selectModel(DiagnosisModelOption.vmamba);
    expect(
      container.read(diagnosisControllerProvider).selectedModel,
      DiagnosisModelOption.vmamba,
    );
  });

  test('M4 14 upload 100 percent changes state to processing', () async {
    final completer = Completer<DiagnosisResult>();
    final api = FakeDiagnosisApi()
      ..onCreate = (image, model, progress) {
        progress?.call(100, 100);
        return completer.future;
      };
    final container = diagnosisContainer(api);
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    final future = container
        .read(diagnosisControllerProvider.notifier)
        .analyze();
    await Future<void>.delayed(Duration.zero);
    expect(
      container.read(diagnosisControllerProvider).status,
      DiagnosisStatus.processing,
    );
    completer.complete(testDiagnosisResult());
    await future;
  });

  test('M4 15 create success stores real result', () async {
    final api = FakeDiagnosisApi();
    final container = diagnosisContainer(api);
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    final result = await container
        .read(diagnosisControllerProvider.notifier)
        .analyze();
    expect(result?.id, 'diagnosis-1');
    expect(
      container.read(diagnosisControllerProvider).status,
      DiagnosisStatus.success,
    );
  });

  test('M4 16 failed create is not automatically retried', () async {
    final api = FakeDiagnosisApi()
      ..onCreate = (_, _, _) async =>
          throw apiError(503, 'AI_SERVICE_UNAVAILABLE', 'AI lỗi');
    final container = diagnosisContainer(api);
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    await container.read(diagnosisControllerProvider.notifier).analyze();
    expect(api.createCalls, 1);
  });

  test('M4 17 double submit is blocked', () async {
    final completer = Completer<DiagnosisResult>();
    final api = FakeDiagnosisApi()..onCreate = (_, _, _) => completer.future;
    final container = diagnosisContainer(api);
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    final first = container
        .read(diagnosisControllerProvider.notifier)
        .analyze();
    final second = await container
        .read(diagnosisControllerProvider.notifier)
        .analyze();
    expect(second, isNull);
    expect(api.createCalls, 1);
    completer.complete(testDiagnosisResult());
    await first;
  });

  for (final item in [
    (18, 413, 'FILE_TOO_LARGE', 'Dung lượng'),
    (19, 415, 'UNSUPPORTED_MEDIA_TYPE', 'JPG'),
    (20, 422, 'INVALID_IMAGE', 'hợp lệ'),
    (21, 503, 'AI_SERVICE_UNAVAILABLE', 'không khả dụng'),
    (22, 504, 'AI_SERVICE_TIMEOUT', 'quá thời gian'),
  ]) {
    test('M4 ${item.$1} maps ${item.$3} to friendly state', () async {
      final error = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/api/v1/diagnoses'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/api/v1/diagnoses'),
            statusCode: item.$2,
            headers: Headers.fromMap({
              Headers.contentTypeHeader: ['application/json'],
            }),
            data: {'status': item.$2, 'code': item.$3, 'message': 'raw'},
          ),
        ),
      );
      final api = FakeDiagnosisApi()..onCreate = (_, _, _) async => throw error;
      final container = diagnosisContainer(api);
      await container.read(diagnosisControllerProvider.notifier).pickImage();
      await container.read(diagnosisControllerProvider.notifier).analyze();
      expect(
        container.read(diagnosisControllerProvider).message,
        contains(item.$4),
      );
    });
  }

  test('M4 23 diagnosis 401 clears authenticated session', () async {
    final session = FakeSessionStore();
    final api = FakeDiagnosisApi()
      ..onCreate = (_, _, _) async =>
          throw apiError(401, 'UNAUTHENTICATED', 'Hết hạn');
    final container = diagnosisContainer(api, sessionStore: session);
    await authenticate(container);
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    await container.read(diagnosisControllerProvider.notifier).analyze();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(session.clearAllCalls, greaterThan(0));
  });

  test('M4 24 diagnosis 403 does not log user out', () async {
    final api = FakeDiagnosisApi()
      ..onCreate = (_, _, _) async =>
          throw apiError(403, 'ACCESS_DENIED', 'Không có quyền');
    final container = diagnosisContainer(api);
    await authenticate(container);
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    await container.read(diagnosisControllerProvider.notifier).analyze();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
  });

  test('M4 25 initial result avoids a redundant detail GET', () async {
    final api = FakeDiagnosisApi();
    final container = diagnosisContainer(api);
    await container
        .read(diagnosisControllerProvider.notifier)
        .openResult('diagnosis-1', initialResult: testDiagnosisResult());
    expect(api.getCalls, 0);
  });

  test('M4 26 deep result route loads detail by id', () async {
    final api = FakeDiagnosisApi();
    final container = diagnosisContainer(api);
    await container
        .read(diagnosisControllerProvider.notifier)
        .openResult('deep-id');
    expect(api.getCalls, 1);
    expect(container.read(diagnosisControllerProvider).result?.id, 'deep-id');
  });

  test('M4 27 delete success clears result', () async {
    final api = FakeDiagnosisApi();
    final container = diagnosisContainer(api);
    await container
        .read(diagnosisControllerProvider.notifier)
        .openResult('diagnosis-1', initialResult: testDiagnosisResult());
    expect(
      await container
          .read(diagnosisControllerProvider.notifier)
          .deleteCurrent(),
      isTrue,
    );
    expect(container.read(diagnosisControllerProvider).result, isNull);
    expect(api.deleteCalls, 1);
  });

  test('M4 28 delete failure preserves visible result', () async {
    final api = FakeDiagnosisApi()
      ..onDelete = (_) async =>
          throw apiError(503, 'SERVICE_UNAVAILABLE', 'Không thể xóa');
    final container = diagnosisContainer(api);
    await container
        .read(diagnosisControllerProvider.notifier)
        .openResult('diagnosis-1', initialResult: testDiagnosisResult());
    expect(
      await container
          .read(diagnosisControllerProvider.notifier)
          .deleteCurrent(),
      isFalse,
    );
    expect(
      container.read(diagnosisControllerProvider).result?.id,
      'diagnosis-1',
    );
  });

  test('M4 29 analyze another clears previous result', () async {
    final container = diagnosisContainer(FakeDiagnosisApi());
    await container
        .read(diagnosisControllerProvider.notifier)
        .openResult('diagnosis-1', initialResult: testDiagnosisResult());
    container.read(diagnosisControllerProvider.notifier).analyzeAnother();
    expect(container.read(diagnosisControllerProvider).result, isNull);
  });

  test('M4 30 multipart uses exact image/modelType fields and CSRF', () async {
    late RequestOptions createRequest;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter((options) {
      if (options.path.endsWith('/csrf')) {
        return jsonResponse({
          'token': 'csrf-token',
          'headerName': 'X-CSRF-TOKEN',
          'parameterName': '_csrf',
        });
      }
      createRequest = options;
      return jsonResponse({
        'id': 'd-1',
        'originalImageUrl': '/original',
        'resultImageUrl': '/result',
      }, statusCode: 201);
    });
    dio.httpClientAdapter = adapter;
    final client = ApiClient(dio);
    final csrf = CsrfController(client);
    dio.interceptors.add(CsrfInterceptor(() => csrf.token));
    await DiagnosisApi(
      client,
      csrf,
    ).createDiagnosis(testSelectedImage(), DiagnosisModelOption.vmamba);
    final data = createRequest.data! as FormData;
    expect(data.fields.map((entry) => entry.key), contains('modelType'));
    expect(data.fields.single.value, 'YOLO26n-VMamba-seg');
    expect(data.files.single.key, 'image');
    expect(createRequest.headers['X-CSRF-TOKEN'], 'csrf-token');
  });

  testWidgets('M4 31 submit button is disabled before image selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(const DiagnosisScreen(), FakeDiagnosisApi()),
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('analyze-button')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('M4 32 selected image preview is displayed', (tester) async {
    await tester.pumpWidget(
      testApp(const DiagnosisScreen(), FakeDiagnosisApi()),
    );
    await tester.tap(find.byKey(const Key('pick-image-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected-image-preview')), findsOneWidget);
    expect(find.text('sample.png'), findsOneWidget);
  });

  testWidgets('M4 33 processing state shows honest inference text', (
    tester,
  ) async {
    final completer = Completer<DiagnosisResult>();
    final api = FakeDiagnosisApi()
      ..onCreate = (_, _, progress) {
        progress?.call(1, 1);
        return completer.future;
      };
    await tester.pumpWidget(testApp(const DiagnosisScreen(), api));
    await tester.tap(find.byKey(const Key('pick-image-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('analyze-button')));
    await tester.pump();
    expect(find.text('Mô hình đang xử lý ảnh...'), findsOneWidget);
  });

  testWidgets(
    'M4 34 result shows model metrics and disclaimer without winner claim',
    (tester) async {
      final result = testDiagnosisResult(
        modelType: 'YOLO26n-VMamba-seg',
        modelCategory: 'VMAMBA',
      );
      final api = FakeDiagnosisApi();
      await tester.pumpWidget(
        testApp(
          DiagnosisResultScreen(id: result.id, initialResult: result),
          api,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('YOLO26n-VMamba-seg'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('62.4%'), findsOneWidget);
      expect(find.text('148.5 ms'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('result-disclaimer')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('result-disclaimer')), findsOneWidget);
      expect(find.textContaining('model tốt hơn'), findsNothing);
    },
  );

  testWidgets('M4 35 authenticated image exposes loading and error retry', (
    tester,
  ) async {
    final completer = Completer<Uint8List>();
    final api = FakeDiagnosisApi()..onLoadImage = (_) => completer.future;
    await tester.pumpWidget(
      testApp(
        const AuthenticatedImage(url: '/image', semanticLabel: 'Ảnh bảo vệ'),
        api,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.completeError(
      apiError(404, 'FILE_NOT_FOUND', 'Không tìm thấy ảnh'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('authenticated-image-retry')), findsOneWidget);
  });

  testWidgets(
    'M4 36 authenticated image renders bytes from shared repository',
    (tester) async {
      final api = FakeDiagnosisApi();
      await tester.pumpWidget(
        testApp(
          const AuthenticatedImage(url: '/image', semanticLabel: 'Ảnh bảo vệ'),
          api,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(api.imageCalls, 1);
    },
  );

  testWidgets('M4 37 fullscreen uses built-in InteractiveViewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        const FullscreenImageScreen(
          arguments: AuthenticatedImageArguments(
            url: '/image',
            title: 'Overlay',
          ),
        ),
        FakeDiagnosisApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('fullscreen-interactive-viewer')),
      findsOneWidget,
    );
    expect(find.byTooltip('Đóng ảnh toàn màn hình'), findsOneWidget);
  });

  testWidgets('M4 38 phone 320 and tablet layouts do not overflow', (
    tester,
  ) async {
    for (final size in [const Size(320, 700), const Size(900, 1000)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        testApp(const DiagnosisScreen(), FakeDiagnosisApi()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  test('M4 39 diagnosis feature contains no legacy mock content', () {
    final source = Directory('lib/features/diagnosis')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join();
    expect(source.toLowerCase(), isNot(contains('kết quả mock')));
    expect(source, isNot(contains('M1 chưa')));
  });

  test('M4 40 router supports result id and authenticated image routes', () {
    final source = File('lib/navigation/app_router.dart').readAsStringSync();
    expect(source, contains("path: 'result/:id'"));
    expect(source, contains('AppRoutes.diagnosisImage'));
    expect(
      File('lib/features/dashboard/dashboard_screen.dart').readAsStringSync(),
      contains('diagnosisResult(activity.id)'),
    );
  });

  test(
    'M4 41 partial upload updates real progress without faking inference',
    () async {
      final completer = Completer<DiagnosisResult>();
      final api = FakeDiagnosisApi()
        ..onCreate = (_, _, progress) {
          progress?.call(40, 100);
          return completer.future;
        };
      final container = diagnosisContainer(api);
      await container.read(diagnosisControllerProvider.notifier).pickImage();
      final pending = container
          .read(diagnosisControllerProvider.notifier)
          .analyze();
      await Future<void>.delayed(Duration.zero);
      final state = container.read(diagnosisControllerProvider);
      expect(state.status, DiagnosisStatus.uploading);
      expect(state.uploadProgress, 0.4);
      completer.complete(testDiagnosisResult());
      await pending;
    },
  );

  test('M4 42 DELETE sends CSRF and exact diagnosis URL', () async {
    late RequestOptions deleteRequest;
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
    final adapter = FakeHttpClientAdapter((options) {
      if (options.path.endsWith('/csrf')) {
        return jsonResponse({
          'token': 'csrf-token',
          'headerName': 'X-CSRF-TOKEN',
          'parameterName': '_csrf',
        });
      }
      deleteRequest = options;
      return ResponseBody.fromBytes(const [], 204);
    });
    dio.httpClientAdapter = adapter;
    final client = ApiClient(dio);
    final csrf = CsrfController(client);
    dio.interceptors.add(CsrfInterceptor(() => csrf.token));
    await DiagnosisApi(client, csrf).deleteDiagnosis('d-1');
    expect(deleteRequest.method, 'DELETE');
    expect(deleteRequest.path, '/api/v1/diagnoses/d-1');
    expect(deleteRequest.headers['X-CSRF-TOKEN'], 'csrf-token');
  });

  testWidgets('M4 43 authenticated image 401 clears auth session', (
    tester,
  ) async {
    final session = FakeSessionStore();
    final api = FakeDiagnosisApi()
      ..onLoadImage = (_) async =>
          throw apiError(401, 'UNAUTHENTICATED', 'Hết hạn');
    final container = diagnosisContainer(api, sessionStore: session);
    await authenticate(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AuthenticatedImage(url: '/image', semanticLabel: 'Ảnh'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(session.clearAllCalls, greaterThan(0));
  });

  testWidgets('M4 44 authenticated image 403 keeps auth state', (tester) async {
    final api = FakeDiagnosisApi()
      ..onLoadImage = (_) async =>
          throw apiError(403, 'ACCESS_DENIED', 'Không có quyền');
    final container = diagnosisContainer(api);
    await authenticate(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: AuthenticatedImage(url: '/image', semanticLabel: 'Ảnh'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.authenticated,
    );
    expect(find.text('Không có quyền'), findsOneWidget);
  });

  testWidgets('M4 45 delete button requires explicit confirmation', (
    tester,
  ) async {
    final result = testDiagnosisResult();
    await tester.pumpWidget(
      testApp(
        DiagnosisResultScreen(id: result.id, initialResult: result),
        FakeDiagnosisApi(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('delete-diagnosis-button')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('delete-diagnosis-button')));
    await tester.pumpAndSettle();
    expect(find.text('Xóa kết quả?'), findsOneWidget);
    expect(find.byKey(const Key('confirm-delete-diagnosis')), findsOneWidget);
  });

  test('M4 46 create and delete invalidate dashboard state', () async {
    final api = FakeDiagnosisApi();
    final container = diagnosisContainer(api);
    await container.read(dashboardControllerProvider.notifier).load();
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.empty,
    );
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    await container.read(diagnosisControllerProvider.notifier).analyze();
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.initial,
    );
    await container.read(diagnosisControllerProvider.notifier).deleteCurrent();
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.initial,
    );
  });
}
