import 'dart:io';

import 'package:app_polyp/app/app_theme.dart';
import 'package:app_polyp/app/legacy_polypvision_app.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/auth/login_screen.dart';
import 'package:app_polyp/features/comparison/comparison_api.dart';
import 'package:app_polyp/features/comparison/comparison_controller.dart';
import 'package:app_polyp/features/comparison/comparison_result_screen.dart';
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/dashboard/dashboard_state.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_api.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_result_screen.dart';
import 'package:app_polyp/features/diagnosis/fullscreen_image_screen.dart';
import 'package:app_polyp/features/history/history_api.dart';
import 'package:app_polyp/features/history/history_controller.dart';
import 'package:app_polyp/features/history/history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M7 invalid release configuration is safe and sends no request', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final authApi = FakeAuthApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authApiProvider.overrideWithValue(authApi)],
        child: const LegacyPolypVisionApp(
          configurationError: 'https://private-host.example/secret',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cấu hình kết nối không hợp lệ'), findsOneWidget);
    expect(find.textContaining('HTTPS'), findsOneWidget);
    expect(find.textContaining('private-host'), findsNothing);
    expect(find.textContaining('10.0.2.2'), findsNothing);
    expect(authApi.meCalls, 0);
    expect(tester.takeException(), isNull);
  });

  test('M7 launcher assets are generated and are not the Flutter template', () {
    final sourceIcon = File('assets/branding/app_icon.png');
    final foreground = File('assets/branding/app_icon_foreground.png');
    final launcher = File(
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    );
    final adaptive = File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();

    expect(sourceIcon.lengthSync(), greaterThan(10000));
    expect(foreground.lengthSync(), greaterThan(10000));
    expect(launcher.lengthSync(), greaterThan(1000));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(adaptive, contains('@color/ic_launcher_background'));
    expect(
      File('assets/branding/app_icon_chroma_source.png').existsSync(),
      isFalse,
    );
  });

  test('M7 native splash defines light dark and Android 12 resources', () {
    final light = File(
      'android/app/src/main/res/values-v31/styles.xml',
    ).readAsStringSync();
    final dark = File(
      'android/app/src/main/res/values-night-v31/styles.xml',
    ).readAsStringSync();

    expect(light, contains('#F5F9FC'));
    expect(dark, contains('#0B1D2A'));
    expect(light, contains('@drawable/android12splash'));
    expect(
      File('android/app/src/main/res/drawable-xxxhdpi/splash.png').existsSync(),
      isTrue,
    );
  });

  test('M7 release signing and cleartext policies fail closed', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final mainManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final debugManifest = File(
      'android/app/src/debug/AndroidManifest.xml',
    ).readAsStringSync();

    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(mainManifest, contains('android:usesCleartextTraffic="false"'));
    expect(debugManifest, contains('android:usesCleartextTraffic="true"'));
  });

  test('M7 Android requests only INTERNET permission', () {
    final manifests = Directory('android/app/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('AndroidManifest.xml'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    final permissions = RegExp(
      r'<uses-permission\s+android:name="([^"]+)"',
    ).allMatches(manifests).map((match) => match.group(1)).toSet();

    expect(permissions, {'android.permission.INTERNET'});
    expect(manifests, isNot(contains('READ_MEDIA_IMAGES')));
    expect(manifests, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
  });

  test('M7 logout clears all user-scoped feature state', () async {
    final authApi = FakeAuthApi();
    final session = FakeSessionStore();
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(authApi),
        authSessionStoreProvider.overrideWithValue(session),
        dashboardApiProvider.overrideWithValue(
          FakeDashboardApi()..onFetch = () async => testDashboard(),
        ),
        diagnosisApiProvider.overrideWithValue(FakeDiagnosisApi()),
        diagnosisImagePickerProvider.overrideWithValue(
          FakeDiagnosisImagePicker(),
        ),
        comparisonApiProvider.overrideWithValue(FakeComparisonApi()),
        historyApiProvider.overrideWithValue(FakeHistoryApi()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(authControllerProvider.notifier)
        .login(const LoginRequest(email: 'an@example.com', password: 'secret'));
    await container.read(dashboardControllerProvider.notifier).load();
    await container.read(diagnosisControllerProvider.notifier).pickImage();
    await container.read(diagnosisControllerProvider.notifier).analyze();
    await container.read(comparisonControllerProvider.notifier).pickImage();
    await container.read(comparisonControllerProvider.notifier).compare();
    await container.read(diagnosisHistoryControllerProvider.notifier).load();
    await container.read(comparisonHistoryControllerProvider.notifier).load();

    await container.read(authControllerProvider.notifier).logout();

    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(
      container.read(dashboardControllerProvider).status,
      DashboardStatus.initial,
    );
    expect(container.read(diagnosisControllerProvider).selectedImage, isNull);
    expect(container.read(diagnosisControllerProvider).result, isNull);
    expect(container.read(comparisonControllerProvider).selectedImage, isNull);
    expect(container.read(comparisonControllerProvider).result, isNull);
    expect(container.read(diagnosisHistoryControllerProvider).items, isEmpty);
    expect(container.read(comparisonHistoryControllerProvider).items, isEmpty);
    expect(session.clearAllCalls, greaterThan(0));
  });

  test('M7 a fresh process bootstrap never assumes authentication', () async {
    final authApi = FakeAuthApi();
    final session = FakeSessionStore();
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(authApi),
        authSessionStoreProvider.overrideWithValue(session),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(authControllerProvider).status, AuthStatus.checking);
    await container.read(authControllerProvider.notifier).bootstrap();
    expect(
      container.read(authControllerProvider).status,
      AuthStatus.unauthenticated,
    );
    expect(authApi.meCalls, 1);
    expect(session.clearAllCalls, 1);
  });

  for (final width in [600.0, 720.0, 800.0, 839.0, 840.0, 1024.0, 1280.0]) {
    testWidgets('M7 comparison layout at ${width.toInt()} px', (tester) async {
      tester.view
        ..physicalSize = Size(width, 1100)
        ..devicePixelRatio = 1;
      addTearDown(() {
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });
      final result = testComparisonResult();
      await tester.pumpWidget(
        _featureApp(
          ComparisonResultScreen(
            comparisonGroupId: result.comparisonGroupId,
            initialResult: result,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final split = find.byKey(const Key('comparison-tablet-split'));
      final tabs = find.byKey(const Key('comparison-phone-tabs'));
      expect(split, width >= 840 ? findsOneWidget : findsNothing);
      expect(tabs, width >= 840 ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [600.0, 720.0, 800.0, 840.0, 1024.0, 1280.0]) {
    testWidgets('M7 tablet shell at ${width.toInt()} px has no overflow', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view
        ..physicalSize = Size(width, 900)
        ..devicePixelRatio = 1;
      addTearDown(() {
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });
      await tester.pumpWidget(_authenticatedRootApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(
          Key(
            width >= 840
                ? 'expanded-navigation-rail'
                : 'medium-navigation-rail',
          ),
        ),
        findsOneWidget,
        reason: 'width=$width',
      );
      expect(tester.takeException(), isNull, reason: 'width=$width');
    });
  }

  testWidgets('M7 Galaxy A51-like portrait and landscape do not overflow', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    for (final size in [const Size(412, 915), const Size(915, 412)]) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(_authenticatedRootApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull, reason: 'size=$size');
    }
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
  });

  testWidgets('M7 large text login remains scrollable without overflow', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 640)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    await tester.pumpWidget(_featureApp(const LoginScreen(), textScale: 2));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('M7 large text diagnosis result has no overflow', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final result = testDiagnosisResult();
    await tester.pumpWidget(
      _featureApp(
        DiagnosisResultScreen(id: result.id, initialResult: result),
        textScale: 1.8,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kết quả phân đoạn'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('M7 native back returns diagnosis result to its form', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final result = testDiagnosisResult();
    await tester.pumpWidget(
      _featureApp(
        _PushHarness(
          destination: DiagnosisResultScreen(
            id: result.id,
            initialResult: result,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('push-destination')));
    await tester.pumpAndSettle();
    expect(find.text('Kết quả phân đoạn'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-destination')), findsOneWidget);
  });

  testWidgets('M7 native back closes fullscreen image', (tester) async {
    await tester.pumpWidget(
      _featureApp(
        const _PushHarness(
          destination: FullscreenImageScreen(
            arguments: AuthenticatedImageArguments(
              url: '/image',
              title: 'Ảnh kết quả',
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('push-destination')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('fullscreen-interactive-viewer')),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('push-destination')), findsOneWidget);
  });

  testWidgets('M7 history detail back returns to history', (tester) async {
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
              Scaffold(body: Text('detail:${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_historyRouterApp(router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sample.jpg'));
    await tester.pumpAndSettle();
    expect(find.text('detail:diagnosis-1'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('sample.jpg'), findsOneWidget);
  });

  test('M7 production sources contain no mock data and keep disclaimer', () {
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(sources.toLowerCase(), isNot(contains('mock data')));
    expect(sources, isNot(contains('MockSessionController')));
    expect(
      File('lib/shared/widgets/research_disclaimer.dart').readAsStringSync(),
      contains('không thay thế'),
    );
  });
}

Widget _featureApp(Widget child, {double textScale = 1}) {
  return ProviderScope(
    overrides: [
      authApiProvider.overrideWithValue(FakeAuthApi()),
      authSessionStoreProvider.overrideWithValue(FakeSessionStore()),
      dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
      diagnosisApiProvider.overrideWithValue(FakeDiagnosisApi()),
      diagnosisImagePickerProvider.overrideWithValue(
        FakeDiagnosisImagePicker(),
      ),
      comparisonApiProvider.overrideWithValue(FakeComparisonApi()),
      historyApiProvider.overrideWithValue(FakeHistoryApi()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
}

Widget _historyRouterApp(GoRouter router) {
  return ProviderScope(
    overrides: [
      historyApiProvider.overrideWithValue(FakeHistoryApi()),
      authApiProvider.overrideWithValue(FakeAuthApi()),
      authSessionStoreProvider.overrideWithValue(FakeSessionStore()),
      dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

Widget _authenticatedRootApp() {
  final authApi = FakeAuthApi()..onMe = () async => testUser;
  return ProviderScope(
    overrides: [
      authApiProvider.overrideWithValue(authApi),
      authSessionStoreProvider.overrideWithValue(FakeSessionStore()),
      dashboardApiProvider.overrideWithValue(FakeDashboardApi()),
    ],
    child: const LegacyPolypVisionApp(),
  );
}

class _PushHarness extends StatelessWidget {
  const _PushHarness({required this.destination});

  final Widget destination;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        key: const Key('push-destination'),
        onPressed: () => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute<void>(builder: (_) => destination)),
        child: const Text('Mở'),
      ),
    );
  }
}
