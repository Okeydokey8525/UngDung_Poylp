import 'dart:io';

import 'package:app_polyp/app/app_theme.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/legal/disclaimer_screen.dart';
import 'package:app_polyp/features/legal/privacy_screen.dart';
import 'package:app_polyp/features/legal/terms_screen.dart';
import 'package:app_polyp/navigation/direct_ai_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M7 legal routes and current mobile scope', () {
    testWidgets('1 Terms, Privacy and Disclaimer routes open', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          directAiRepositoryProvider.overrideWithValue(_LegalRepository()),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(directAiRouterProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final entry in const [
        (DirectAiRoutes.terms, Key('mobile-terms-screen')),
        (DirectAiRoutes.privacy, Key('mobile-privacy-screen')),
        (DirectAiRoutes.disclaimer, Key('mobile-disclaimer-screen')),
      ]) {
        router.go(entry.$1);
        await tester.pumpAndSettle();
        expect(find.byKey(entry.$2), findsOneWidget, reason: entry.$1);
      }
    });

    test('2 legal pages contain no placeholder or backend-sync promise', () {
      final source = _legalSource();
      expect(source, isNot(contains('placeholder')));
      expect(source, isNot(contains('đồng bộ từ backend')));
      expect(source, isNot(contains('kết quả mock')));
      expect(source, isNot(contains('M1')));
    });

    test('3 Terms does not require mobile login or account management', () {
      final terms = _source('terms_screen.dart');
      expect(terms, contains('không yêu cầu đăng ký, đăng nhập'));
      expect(terms, isNot(contains('phải đăng nhập')));
      expect(terms, isNot(contains('quản lý mật khẩu')));
      expect(terms, isNot(contains('khóa tài khoản')));
      expect(terms, isNot(contains('xác minh email')));
    });

    test('4 Terms describes input, results and research limitations', () {
      final terms = _source('terms_screen.dart');
      expect(terms, contains('chủ động chọn ảnh nội soi'));
      expect(terms, contains('FastAPI'));
      expect(terms, contains('Độ tin cậy của dự đoán'));
      expect(terms, contains('false positive'));
      expect(terms, contains('false negative'));
    });

    test('5 Privacy states the Direct AI data flow accurately', () {
      final privacy = _source('privacy_screen.dart');
      expect(privacy, contains('PolypVision Mobile Direct AI'));
      expect(privacy, contains('Flutter gửi ảnh trực tiếp tới FastAPI'));
      expect(privacy, contains('AI_BASE_URL'));
      expect(privacy, contains('metadata kỹ thuật'));
    });

    test('6 Privacy separates current storage from future features', () {
      final privacy = _source('privacy_screen.dart');
      expect(privacy, contains('Không tạo Local History hoặc cloud history'));
      expect(privacy, contains('Không có user database'));
      expect(privacy, contains('chưa có trong phiên bản hiện tại'));
      expect(privacy, isNot(contains('lưu lịch sử trên server')));
    });

    test(
      '7 Privacy makes no unsupported immediate server-deletion promise',
      () {
        final privacy = _source('privacy_screen.dart');
        expect(
          privacy,
          contains('không cam kết thời điểm xóa dữ liệu trên server'),
        );
        expect(privacy, isNot(contains('server xóa ngay sau xử lý.')));
        expect(privacy, isNot(contains('không thu thập bất kỳ dữ liệu nào')));
      },
    );

    test('8 current mobile has no analytics or advertising integration', () {
      final privacy = _source('privacy_screen.dart');
      expect(
        privacy,
        contains('không tích hợp quảng cáo, analytics hoặc dịch vụ chia sẻ'),
      );
      expect(privacy, isNot(contains('chia sẻ dữ liệu với bất kỳ ai')));
    });
  });

  group('M7 medical wording', () {
    test('9 official disclaimer remains verbatim', () {
      final source = _legalSource(includeSharedDisclaimer: true);
      expect(
        source,
        contains(
          'Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, '
          'không thay thế chẩn đoán hoặc quyết định chuyên môn của bác sĩ.',
        ),
      );
    });

    test('10 Disclaimer warns about false positive and false negative', () {
      final disclaimer = _source('disclaimer_screen.dart');
      expect(disclaimer, contains('bỏ sót vùng polyp (false negative)'));
      expect(disclaimer, contains('đánh dấu nhầm vùng không phải polyp'));
      expect(disclaimer, contains('(false positive)'));
    });

    test(
      '11 confidence is not presented as accuracy or disease probability',
      () {
        final source = _legalSource();
        expect(source, contains('Độ tin cậy của dự đoán'));
        expect(source, contains('không phải xác suất mắc bệnh'));
        expect(source, isNot(contains('Độ chính xác')));
        expect(source, isNot(contains('độ chính xác của ca bệnh')));
      },
    );

    test(
      '12 legal content makes no diagnosis, cancer or certification claim',
      () {
        final source = _legalSource();
        expect(source, isNot(contains('AI chẩn đoán')));
        expect(source, isNot(contains('PolypVision chẩn đoán')));
        expect(source, isNot(contains('phát hiện ung thư')));
        expect(RegExp(r'\b(?:FDA|CE)\b').hasMatch(source), isFalse);
      },
    );

    test('13 professional review and treatment limits are explicit', () {
      final disclaimer = _source('disclaimer_screen.dart');
      expect(disclaimer, contains('nhân viên y tế có chuyên môn'));
      expect(disclaimer, contains('cơ sở duy nhất cho quyết định điều trị'));
      expect(disclaimer, contains('một ảnh không đủ để kết luận'));
    });
  });

  group('M7 legal responsive and theme regression', () {
    for (final size in const [
      Size(320, 568),
      Size(412, 915),
      Size(800, 1000),
    ]) {
      testWidgets('14 legal pages do not overflow at $size', (tester) async {
        for (final screen in const [
          TermsScreen(),
          PrivacyScreen(),
          DisclaimerScreen(),
        ]) {
          await _pumpLegal(tester, screen, size: size);
          expect(tester.takeException(), isNull, reason: '$size $screen');
        }
      });
    }

    testWidgets('15 legal pages support text scale 1.3', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final screen in const [
        TermsScreen(),
        PrivacyScreen(),
        DisclaimerScreen(),
      ]) {
        await _pumpLegal(tester, screen, size: const Size(320, 568));
        expect(tester.takeException(), isNull, reason: '$screen');
      }
    });

    testWidgets('16 legal pages render safely in dark mode', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      for (final screen in const [
        TermsScreen(),
        PrivacyScreen(),
        DisclaimerScreen(),
      ]) {
        await _pumpLegal(tester, screen, size: const Size(412, 915));
        expect(
          Theme.of(tester.element(find.byType(Scaffold))).brightness,
          Brightness.dark,
        );
        expect(tester.takeException(), isNull, reason: '$screen');
      }
    });
  });
}

String _source(String name) => File(
  'lib/features/legal/$name',
).readAsStringSync().replaceAll(RegExp(r"'\s*'"), '');

String _legalSource({bool includeSharedDisclaimer = false}) {
  final source = [
    _source('terms_screen.dart'),
    _source('privacy_screen.dart'),
    _source('disclaimer_screen.dart'),
  ];
  if (includeSharedDisclaimer) {
    source.add(
      File('lib/shared/widgets/research_disclaimer.dart').readAsStringSync(),
    );
  }
  return source.join('\n');
}

Future<void> _pumpLegal(
  WidgetTester tester,
  Widget screen, {
  required Size size,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: screen,
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
}

final class _LegalRepository implements AiRepository {
  @override
  Future<AiHealthResponse> getHealth() async => AiHealthResponse.fromJson({
    'requestId': 'm7-legal-health',
    'status': 'ok',
    'service': 'PolypVision AI Service',
    'ready': true,
    'device': 'cpu',
    'readyModels': 2,
    'totalModels': 2,
    'timestamp': '2026-08-08T00:00:00Z',
  });

  @override
  Future<AiModelsResponse> getModels() async => AiModelsResponse.fromJson({
    'requestId': 'm7-legal-models',
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

  @override
  Future<AiInferenceResult> infer({
    required AiImageUpload image,
    required String modelKey,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) => throw StateError('Legal routes must not call inference');

  @override
  Future<AiComparisonResult> compare({
    required AiImageUpload image,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) => throw StateError('Legal routes must not call comparison');
}
