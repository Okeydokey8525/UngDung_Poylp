import 'dart:async';

import 'package:app_polyp/app/polypvision_app.dart';
import 'package:app_polyp/app/theme_controller.dart';
import 'package:app_polyp/core/config/ai_service_config.dart';
import 'package:app_polyp/core/network/ai_api_exception.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/navigation/direct_ai_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

AiHealthResponse _health({
  String status = 'ok',
  bool ready = true,
  int readyModels = 2,
}) => AiHealthResponse(
  requestId: 'm3-health-request',
  status: status,
  service: 'PolypVision AI Service',
  ready: ready,
  device: 'cpu',
  readyModels: readyModels,
  totalModels: 2,
  timestamp: DateTime.utc(2026, 8, 5),
);

AiModelsResponse _models({bool vmambaReady = true}) => AiModelsResponse(
  requestId: 'm3-models-request',
  models: [
    const AiModelInfo(
      key: 'YOLO26n-seg',
      name: 'Baseline từ provider',
      family: 'baseline',
      ready: true,
    ),
    AiModelInfo(
      key: 'YOLO26n-VMamba-seg',
      name: 'VMamba từ provider',
      family: 'vmamba',
      ready: vmambaReady,
    ),
  ],
);

final class _FakeDirectAiRepository implements AiRepository {
  Future<AiHealthResponse> Function()? onHealth;
  Future<AiModelsResponse> Function()? onModels;
  int healthCalls = 0;
  int modelCalls = 0;
  int inferCalls = 0;
  int compareCalls = 0;

  @override
  Future<AiHealthResponse> getHealth() {
    healthCalls++;
    return onHealth?.call() ?? Future.value(_health());
  }

  @override
  Future<AiModelsResponse> getModels() {
    modelCalls++;
    return onModels?.call() ?? Future.value(_models());
  }

  @override
  Future<AiInferenceResult> infer({
    required AiImageUpload image,
    required String modelKey,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) {
    inferCalls++;
    throw StateError('M3 must not call inference');
  }

  @override
  Future<AiComparisonResult> compare({
    required AiImageUpload image,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) {
    compareCalls++;
    throw StateError('M3 must not call comparison');
  }
}

typedef _DirectHarness = ({
  ProviderContainer container,
  _FakeDirectAiRepository repository,
  FakeAuthApi authApi,
});

Future<_DirectHarness> _pumpDirectApp(
  WidgetTester tester, {
  _FakeDirectAiRepository? repository,
  Size size = const Size(390, 2400),
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  final directRepository = repository ?? _FakeDirectAiRepository();
  final authApi = FakeAuthApi();
  final config = AiServiceConfig.fromValue(
    'http://10.0.2.2:8000',
    isRelease: false,
  );
  final container = ProviderContainer(
    overrides: [
      aiServiceConfigProvider.overrideWithValue(config),
      directAiRepositoryProvider.overrideWithValue(directRepository),
      authApiProvider.overrideWithValue(authApi),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PolypVisionApp(),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return (container: container, repository: directRepository, authApi: authApi);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M3 direct runtime and router', () {
    testWidgets('1 app opens Home AI without splash, login, or /me', (
      tester,
    ) async {
      final harness = await _pumpDirectApp(tester);

      expect(find.byKey(const Key('ai-home-screen')), findsOneWidget);
      expect(find.text('PolypVision'), findsOneWidget);
      expect(find.text('Đang kiểm tra phiên đăng nhập…'), findsNothing);
      expect(find.text('Đăng nhập'), findsNothing);
      expect(harness.authApi.meCalls, 0);
      expect(harness.repository.healthCalls, 1);
      expect(harness.repository.modelCalls, 1);
      expect(harness.repository.inferCalls, 0);
      expect(harness.repository.compareCalls, 0);
    });

    testWidgets('2 unknown route has a safe Home fallback', (tester) async {
      final harness = await _pumpDirectApp(tester);
      harness.container.read(directAiRouterProvider).go('/khong-ton-tai');
      await tester.pumpAndSettle();

      expect(find.text('Đường dẫn không hợp lệ'), findsOneWidget);
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-home-screen')), findsOneWidget);
    });

    testWidgets('3 bottom navigation changes all four direct tabs', (
      tester,
    ) async {
      await _pumpDirectApp(tester);
      expect(
        find.byKey(const Key('direct-compact-navigation-bar')),
        findsOneWidget,
      );

      await tester.tap(find.text('Phân tích'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-analysis-screen')), findsOneWidget);

      await tester.tap(find.text('So sánh'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-comparison-screen')), findsOneWidget);

      await tester.tap(find.text('Giới thiệu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-about-screen')), findsOneWidget);

      await tester.tap(find.text('Trang chủ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-home-screen')), findsOneWidget);
    });

    testWidgets('4 tablet NavigationRail changes the selected route', (
      tester,
    ) async {
      await _pumpDirectApp(tester, size: const Size(800, 900));
      expect(
        find.byKey(const Key('direct-medium-navigation-rail')),
        findsOneWidget,
      );
      final rail = tester.widget<NavigationRail>(
        find.byKey(const Key('direct-medium-navigation-rail')),
      );
      rail.onDestinationSelected!(2);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-comparison-screen')), findsOneWidget);
    });

    testWidgets('5 direct startup exposes no account destinations', (
      tester,
    ) async {
      await _pumpDirectApp(tester);
      expect(find.text('Lịch sử'), findsNothing);
      expect(find.text('Tài khoản'), findsNothing);
      expect(find.text('Đăng xuất'), findsNothing);
      expect(find.text('Dashboard'), findsNothing);
    });
  });

  group('M3 Home AI', () {
    testWidgets(
      '6 hero, research description, CTA, guide and disclaimer render',
      (tester) async {
        await _pumpDirectApp(tester);
        expect(
          find.text('Phân đoạn polyp đại trực tràng từ ảnh nội soi'),
          findsOneWidget,
        );
        expect(
          find.textContaining('YOLO26n-seg và mô hình tích hợp VMamba'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('home-analyze-cta')), findsOneWidget);
        expect(find.byKey(const Key('home-compare-cta')), findsOneWidget);
        expect(find.text('Chọn ảnh nội soi'), findsOneWidget);
        expect(find.textContaining('không thay thế chẩn đoán'), findsOneWidget);
      },
    );

    testWidgets('7 health loading has accessible progress text', (
      tester,
    ) async {
      final completer = Completer<AiHealthResponse>();
      final repository = _FakeDirectAiRepository()
        ..onHealth = () => completer.future;
      await _pumpDirectApp(tester, repository: repository, settle: false);

      expect(find.text('Đang kiểm tra dịch vụ AI…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      completer.complete(_health());
      await tester.pumpAndSettle();
    });

    testWidgets('8 health ready displays textual state', (tester) async {
      await _pumpDirectApp(tester);
      expect(find.text('Dịch vụ AI đã sẵn sàng'), findsOneWidget);
      expect(find.textContaining('2/2 mô hình sẵn sàng'), findsOneWidget);
    });

    testWidgets('9 health degraded displays textual state', (tester) async {
      final repository = _FakeDirectAiRepository()
        ..onHealth = () async =>
            _health(status: 'degraded', ready: false, readyModels: 1);
      await _pumpDirectApp(tester, repository: repository);
      expect(find.text('Một số mô hình chưa sẵn sàng'), findsOneWidget);
      expect(find.textContaining('1/2 mô hình sẵn sàng'), findsOneWidget);
    });

    testWidgets('10 health unavailable displays textual state', (tester) async {
      final repository = _FakeDirectAiRepository()
        ..onHealth = () async =>
            _health(status: 'unavailable', ready: false, readyModels: 0);
      await _pumpDirectApp(tester, repository: repository);
      expect(find.text('Dịch vụ AI hiện không khả dụng'), findsOneWidget);
    });

    testWidgets('11 connection error is safe and retry refreshes', (
      tester,
    ) async {
      final repository = _FakeDirectAiRepository()
        ..onHealth = () async => throw const AiApiException(
          kind: AiFailureKind.connection,
          message: r'C:\secret\raw DioException',
        );
      await _pumpDirectApp(tester, repository: repository);

      expect(find.text('Không thể kết nối dịch vụ AI'), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
      await tester.tap(find.byKey(const Key('health-error-retry')));
      await tester.pumpAndSettle();
      expect(repository.healthCalls, 2);
    });

    testWidgets('12 invalid health response has a distinct safe state', (
      tester,
    ) async {
      final repository = _FakeDirectAiRepository()
        ..onHealth = () async => throw const AiApiException(
          kind: AiFailureKind.invalidResponse,
          code: 'INVALID_RESPONSE',
          message: 'raw payload',
        );
      await _pumpDirectApp(tester, repository: repository);
      expect(find.text('Phản hồi dịch vụ AI không hợp lệ'), findsOneWidget);
      expect(find.textContaining('raw payload'), findsNothing);
    });

    testWidgets('13 ready health can be manually refreshed without polling', (
      tester,
    ) async {
      final harness = await _pumpDirectApp(tester);
      expect(harness.repository.healthCalls, 1);
      await tester.tap(find.byKey(const Key('health-refresh')));
      await tester.pumpAndSettle();
      expect(harness.repository.healthCalls, 2);
      await tester.pump(const Duration(seconds: 2));
      expect(harness.repository.healthCalls, 2);
    });

    testWidgets('14 model loading does not show hardcoded model cards', (
      tester,
    ) async {
      final completer = Completer<AiModelsResponse>();
      final repository = _FakeDirectAiRepository()
        ..onModels = () => completer.future;
      await _pumpDirectApp(tester, repository: repository, settle: false);
      expect(find.text('Đang tải danh sách mô hình…'), findsOneWidget);
      expect(find.text('Baseline từ provider'), findsNothing);
      completer.complete(_models());
      await tester.pumpAndSettle();
    });

    testWidgets('15 model cards use names and readiness from provider', (
      tester,
    ) async {
      final repository = _FakeDirectAiRepository()
        ..onModels = () async => _models(vmambaReady: false);
      await _pumpDirectApp(tester, repository: repository);
      expect(find.text('Baseline từ provider'), findsOneWidget);
      expect(find.text('VMamba từ provider'), findsOneWidget);
      expect(find.text('Chưa sẵn sàng'), findsOneWidget);
      expect(find.text('Full VMamba'), findsNothing);
    });

    testWidgets('16 models error retries provider', (tester) async {
      final repository = _FakeDirectAiRepository()
        ..onModels = () async => throw const AiApiException(
          kind: AiFailureKind.connection,
          message: 'offline',
        );
      await _pumpDirectApp(tester, repository: repository);
      expect(find.text('Không thể tải danh sách mô hình'), findsOneWidget);
      await tester.tap(find.byKey(const Key('models-retry')));
      await tester.pumpAndSettle();
      expect(repository.modelCalls, 2);
    });

    testWidgets('17 Home CTA opens Analyze', (tester) async {
      await _pumpDirectApp(tester);
      await tester.tap(find.byKey(const Key('home-analyze-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-analysis-screen')), findsOneWidget);
    });

    testWidgets('18 Home CTA opens Compare', (tester) async {
      await _pumpDirectApp(tester);
      await tester.tap(find.byKey(const Key('home-compare-cta')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('direct-comparison-screen')), findsOneWidget);
    });
  });

  group('M3 navigation regression after M4', () {
    testWidgets('19 Analyze uses provider models and waits for an image', (
      tester,
    ) async {
      final harness = await _pumpDirectApp(tester);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.analyze);
      await tester.pumpAndSettle();

      expect(find.text('Phân tích ảnh nội soi'), findsOneWidget);
      expect(find.text('Baseline từ provider'), findsNWidgets(2));
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      final pick = tester.widget<OutlinedButton>(
        find.byKey(const Key('direct-analysis-pick-image')),
      );
      final analyze = tester.widget<FilledButton>(
        find.byKey(const Key('direct-analyze-button')),
      );
      expect(pick.onPressed, isNotNull);
      expect(analyze.onPressed, isNull);
      expect(find.byKey(const Key('analysis-disabled-reason')), findsOneWidget);
      expect(harness.repository.inferCalls, 0);
      expect(find.textContaining('kết quả giả'), findsNothing);
    });

    testWidgets('20 Analyze model error has retry', (tester) async {
      final repository = _FakeDirectAiRepository()
        ..onModels = () async => throw const AiApiException(
          kind: AiFailureKind.connection,
          message: 'offline',
        );
      final harness = await _pumpDirectApp(tester, repository: repository);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.analyze);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analysis-models-retry')));
      await tester.pumpAndSettle();
      expect(repository.modelCalls, 2);
      expect(repository.inferCalls, 0);
    });

    testWidgets('21 Compare uses provider models and waits for an image', (
      tester,
    ) async {
      final harness = await _pumpDirectApp(tester);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.compare);
      await tester.pumpAndSettle();

      expect(find.text('So sánh mô hình'), findsOneWidget);
      expect(find.text('Baseline từ provider'), findsOneWidget);
      expect(find.text('VMamba từ provider'), findsOneWidget);
      final pick = tester.widget<OutlinedButton>(
        find.byKey(const Key('direct-comparison-pick-image')),
      );
      final compare = tester.widget<FilledButton>(
        find.byKey(const Key('direct-compare-button')),
      );
      expect(pick.onPressed, isNotNull);
      expect(compare.onPressed, isNull);
      expect(
        find.byKey(const Key('comparison-disabled-reason')),
        findsOneWidget,
      );
      expect(harness.repository.compareCalls, 0);
      expect(find.textContaining('winner'), findsNothing);
      expect(find.textContaining('tốt hơn'), findsNothing);
      expect(find.textContaining('không thay thế chẩn đoán'), findsOneWidget);
    });

    testWidgets('22 Compare model error retries without calling comparison', (
      tester,
    ) async {
      final repository = _FakeDirectAiRepository()
        ..onModels = () async => throw const AiApiException(
          kind: AiFailureKind.connection,
          message: 'offline',
        );
      final harness = await _pumpDirectApp(tester, repository: repository);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.compare);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comparison-models-retry')));
      await tester.pumpAndSettle();
      expect(repository.modelCalls, 2);
      expect(repository.compareCalls, 0);
    });
  });

  group('M3 About and settings', () {
    testWidgets('23 About explains architecture, models and future scope', (
      tester,
    ) async {
      final harness = await _pumpDirectApp(tester);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.about);
      await tester.pumpAndSettle();

      expect(find.text('Giới thiệu & Cài đặt'), findsOneWidget);
      expect(find.text('Flutter'), findsOneWidget);
      expect(find.text('FastAPI'), findsOneWidget);
      expect(find.text('AI models'), findsOneWidget);
      expect(find.text('Mobile Account & Cloud Sync'), findsOneWidget);
      expect(
        find.textContaining('chưa có trong phiên bản hiện tại'),
        findsOneWidget,
      );
      expect(find.text('Đăng nhập'), findsNothing);
      expect(find.text('Đăng xuất'), findsNothing);
    });

    testWidgets('24 About exposes system, light and dark theme choices', (
      tester,
    ) async {
      final harness = await _pumpDirectApp(tester);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.about);
      await tester.pumpAndSettle();

      for (final preference in AppThemePreference.values) {
        expect(
          find.byKey(Key('direct-theme-${preference.name}')),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(const Key('direct-theme-dark')));
      await tester.pumpAndSettle();
      expect(
        harness.container.read(themeControllerProvider),
        AppThemePreference.dark,
      );
      expect(
        Theme.of(
          tester.element(find.byKey(const Key('direct-about-screen'))),
        ).brightness,
        Brightness.dark,
      );
    });

    testWidgets('25 debug shows AI URL only in settings', (tester) async {
      final harness = await _pumpDirectApp(tester);
      expect(find.byKey(const Key('direct-debug-ai-base-url')), findsNothing);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.about);
      await tester.pumpAndSettle();
      if (kDebugMode) {
        expect(
          find.byKey(const Key('direct-debug-ai-base-url')),
          findsOneWidget,
        );
        expect(find.textContaining('http://10.0.2.2:8000'), findsOneWidget);
      }
      expect(find.textContaining('checkpoint'), findsNothing);
      expect(find.textContaining('cookie'), findsNothing);
    });

    testWidgets('26 legal routes open from About', (tester) async {
      final harness = await _pumpDirectApp(tester);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.about);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('direct-terms-link')));
      await tester.pumpAndSettle();
      expect(find.text('Điều khoản sử dụng'), findsWidgets);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.about);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('direct-privacy-link')));
      await tester.pumpAndSettle();
      expect(find.text('Quyền riêng tư'), findsWidgets);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.about);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('direct-disclaimer-link')));
      await tester.pumpAndSettle();
      expect(find.text('Tuyên bố miễn trừ'), findsOneWidget);
    });
  });

  group('M3 responsive and accessibility', () {
    for (final size in [
      const Size(320, 568),
      const Size(360, 800),
      const Size(412, 915),
      const Size(600, 900),
      const Size(800, 1000),
      const Size(1024, 700),
    ]) {
      testWidgets('27 Home has no overflow at ${size.width.toInt()} px', (
        tester,
      ) async {
        await _pumpDirectApp(tester, size: size);
        expect(tester.takeException(), isNull, reason: 'size=$size');
        if (size.width < 600) {
          expect(
            find.byKey(const Key('direct-compact-navigation-bar')),
            findsOneWidget,
          );
        } else {
          expect(find.byType(NavigationRail), findsOneWidget);
        }
      });
    }

    testWidgets('28 text scale 1.3 has no serious overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpDirectApp(tester, size: const Size(360, 800));
      expect(find.byKey(const Key('ai-home-screen')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('29 system dark mode smoke test', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpDirectApp(tester);
      expect(
        Theme.of(
          tester.element(find.byKey(const Key('ai-home-screen'))),
        ).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('30 disabled actions explain why they cannot be focused', (
      tester,
    ) async {
      final harness = await _pumpDirectApp(tester);
      harness.container.read(directAiRouterProvider).go(DirectAiRoutes.analyze);
      await tester.pumpAndSettle();
      expect(find.textContaining('Hãy chọn một ảnh hợp lệ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
