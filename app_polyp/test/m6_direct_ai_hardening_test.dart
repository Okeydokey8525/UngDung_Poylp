import 'dart:io';

import 'package:app_polyp/app/polypvision_app.dart';
import 'package:app_polyp/core/config/ai_service_config.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/analysis/direct_analysis_controller.dart';
import 'package:app_polyp/features/comparison/direct_comparison_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M6 Direct AI runtime hardening', () {
    test('1 production entrypoint boots only PolypVisionApp', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('PolypVisionApp'));
      expect(main, contains('ProviderScope'));
      expect(main, isNot(contains('LegacyPolypVisionApp')));
      expect(main, isNot(contains('authControllerProvider')));
      expect(main, isNot(contains('appRouterProvider')));
      expect(main, isNot(contains('/api/v1/me')));
    });

    test('2 direct runtime imports no Spring session stack', () {
      final source = _directRuntimeSource();
      for (final forbidden in const [
        'legacy_polypvision_app.dart',
        'navigation/app_router.dart',
        'core/network/api_client.dart',
        'csrf_controller.dart',
        'auth_controller.dart',
        'CookieJar',
        'JSESSIONID',
        '/api/v1/me',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test('3 controllers create no request before an explicit action', () {
      final repository = _CountingRepository();
      final container = ProviderContainer(
        overrides: [directAiRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      container.read(directAnalysisControllerProvider);
      container.read(directComparisonControllerProvider);

      expect(repository.healthCalls, 0);
      expect(repository.modelsCalls, 0);
      expect(repository.inferenceCalls, 0);
      expect(repository.comparisonCalls, 0);
    });

    test('4 debug accepts LAN HTTP while release requires public HTTPS', () {
      expect(
        AiServiceConfig.validateBaseUrl(
          'http://192.168.1.50:8000',
          isRelease: false,
        ),
        isNull,
      );
      expect(
        AiServiceConfig.validateBaseUrl(
          'http://192.168.1.50:8000',
          isRelease: true,
        ),
        isNotNull,
      );
      expect(
        AiServiceConfig.validateBaseUrl(
          'https://ai.example.edu',
          isRelease: true,
        ),
        isNull,
      );
    });

    testWidgets('5 Home is the first screen and requests only health/models', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final repository = _CountingRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [directAiRepositoryProvider.overrideWithValue(repository)],
          child: const PolypVisionApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-home-screen')), findsOneWidget);
      expect(repository.healthCalls, 1);
      expect(repository.modelsCalls, 1);
      expect(repository.inferenceCalls, 0);
      expect(repository.comparisonCalls, 0);
    });
  });

  group('M6 Android and release policy', () {
    test('6 release manifest fails closed for cleartext and backup', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:label="PolypVision"'));
      expect(manifest, contains('android.permission.INTERNET'));
    });

    test('7 debug-only manifest permits LAN cleartext', () {
      final debugManifest = File(
        'android/app/src/debug/AndroidManifest.xml',
      ).readAsStringSync();
      final mainManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(debugManifest, contains('android:usesCleartextTraffic="true"'));
      expect(debugManifest, contains('@xml/network_security_config'));
      expect(mainManifest, isNot(contains('@xml/network_security_config')));
    });

    test(
      '8 release signing is local, fail-closed and never uses debug key',
      () {
        final gradle = File('android/app/build.gradle.kts').readAsStringSync();
        final example = File(
          'android/key.properties.example',
        ).readAsStringSync();
        expect(gradle, contains('rootProject.file("key.properties")'));
        expect(gradle, contains('Missing android/key.properties'));
        expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
        expect(gradle, contains('isMinifyEnabled = true'));
        expect(gradle, contains('isShrinkResources = true'));
        expect(example, contains('storePassword='));
        expect(example, contains('keyPassword='));
      },
    );

    test('9 package ID and version remain explicit', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(gradle, contains('applicationId = "vn.edu.huit.polypvision"'));
      expect(gradle, contains('namespace = "vn.edu.huit.polypvision"'));
      expect(pubspec, contains('version: 1.0.0+1'));
    });

    test('10 Android requests no sensitive or broad storage permission', () {
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
    });
  });

  group('M6 privacy, documentation and responsive smoke', () {
    test(
      '11 direct medical-image runtime does not persist or network-cache',
      () {
        final source = _directRuntimeSource();
        for (final forbidden in const [
          'dart:io',
          'writeAsBytes',
          'Image.network',
          'cached_network_image',
          'analytics',
          'telemetry',
        ]) {
          expect(
            source.toLowerCase(),
            isNot(contains(forbidden.toLowerCase())),
          );
        }
      },
    );

    test('12 official disclaimer is unchanged', () {
      final disclaimer = File(
        'lib/shared/widgets/research_disclaimer.dart',
      ).readAsStringSync();
      expect(
        disclaimer,
        contains(
          'Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, '
          'không thay thế chẩn đoán hoặc quyết định chuyên môn của bác sĩ.',
        ),
      );
    });

    test('13 README documents the Direct AI demo contract', () {
      final readme = File('README.md').readAsStringSync();
      for (final required in const [
        'Flutter → FastAPI → AI models',
        'AI_BASE_URL',
        '10.0.2.2',
        '--host 0.0.0.0',
        'HTTPS',
        'Samsung Galaxy A51',
        'MongoDB không cần',
        'Mobile Account & Cloud Sync',
        'Local History',
      ]) {
        expect(readme, contains(required), reason: required);
      }
      expect(readme, isNot(contains('API_BASE_URL=http://10.0.2.2:8080')));
    });

    for (final size in const [Size(320, 568), Size(412, 915), Size(915, 412)]) {
      testWidgets('14 Direct AI shell has no overflow at $size', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view
            ..resetPhysicalSize()
            ..resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              directAiRepositoryProvider.overrideWithValue(
                _CountingRepository(),
              ),
            ],
            child: const PolypVisionApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ai-home-screen')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

String _directRuntimeSource() {
  const paths = [
    'lib/main.dart',
    'lib/app/polypvision_app.dart',
    'lib/navigation/direct_ai_router.dart',
    'lib/navigation/direct_ai_app_shell.dart',
    'lib/features/home/ai_home_screen.dart',
    'lib/features/analysis/direct_analysis_controller.dart',
    'lib/features/analysis/direct_analysis_state.dart',
    'lib/features/analysis/single_inference_screen.dart',
    'lib/features/comparison/direct_comparison_controller.dart',
    'lib/features/comparison/direct_comparison_state.dart',
    'lib/features/comparison/model_comparison_screen.dart',
    'lib/features/ai/data/ai_repository.dart',
    'lib/features/ai/presentation/providers/ai_providers.dart',
    'lib/shared/medical_image/medical_image.dart',
    'lib/shared/widgets/medical_image_picker_card.dart',
    'lib/shared/widgets/memory_image_card.dart',
    'lib/shared/widgets/fullscreen_memory_image.dart',
  ];
  return paths.map((path) => File(path).readAsStringSync()).join('\n');
}

final class _CountingRepository implements AiRepository {
  int healthCalls = 0;
  int modelsCalls = 0;
  int inferenceCalls = 0;
  int comparisonCalls = 0;

  @override
  Future<AiHealthResponse> getHealth() async {
    healthCalls++;
    return AiHealthResponse.fromJson({
      'requestId': 'm6-health',
      'status': 'ok',
      'service': 'PolypVision AI Service',
      'ready': true,
      'device': 'cpu',
      'readyModels': 2,
      'totalModels': 2,
      'timestamp': '2026-08-08T00:00:00Z',
    });
  }

  @override
  Future<AiModelsResponse> getModels() async {
    modelsCalls++;
    return AiModelsResponse.fromJson({
      'requestId': 'm6-models',
      'models': [
        {
          'key': 'YOLO26n-seg',
          'name': 'YOLO26n-seg',
          'family': 'baseline',
          'ready': true,
        },
        {
          'key': 'YOLO26n-VMamba-seg',
          'name': 'YOLO26n-seg + VMamba',
          'family': 'vmamba',
          'ready': true,
        },
      ],
    });
  }

  @override
  Future<AiInferenceResult> infer({
    required AiImageUpload image,
    required String modelKey,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) {
    inferenceCalls++;
    throw StateError('M6 startup must not call inference');
  }

  @override
  Future<AiComparisonResult> compare({
    required AiImageUpload image,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) {
    comparisonCalls++;
    throw StateError('M6 startup must not call comparison');
  }
}
