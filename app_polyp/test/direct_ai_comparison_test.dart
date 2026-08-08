import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_polyp/app/polypvision_app.dart';
import 'package:app_polyp/core/config/ai_service_config.dart';
import 'package:app_polyp/core/network/ai_api_exception.dart';
import 'package:app_polyp/core/network/ai_user_error_message.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/comparison/direct_comparison_controller.dart';
import 'package:app_polyp/features/comparison/direct_comparison_state.dart';
import 'package:app_polyp/navigation/direct_ai_router.dart';
import 'package:app_polyp/shared/medical_image/medical_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const _jpegBase64 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////'
    '////////////////////////////////////////////////2wBDAf//////////////////'
    '////////////////////////////////////////////////////////////////////wAARCA'
    'ABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAA'
    'AAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQ'
    'J//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAA'
    'AAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFB'
    'ABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABAf/8QAFBEBAAAA'
    'AAAAAAAAAAAAAAAAAP/aAAgBAwEBPxB//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAg'
    'EBPxB//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxB//9k=';

Uint8List get _pngBytes => base64Decode(_pngBase64);
Uint8List get _jpegBytes => base64Decode(_jpegBase64);

XFile _pngFile([String name = 'comparison.png']) =>
    XFile.fromData(_pngBytes, path: name, mimeType: 'image/png');

XFile _jpegFile([String name = 'comparison.jpg']) =>
    XFile.fromData(_jpegBytes, path: name, mimeType: 'image/jpeg');

AiHealthResponse _health() => AiHealthResponse(
  requestId: 'm5-health-request',
  status: 'ok',
  service: 'PolypVision AI Service',
  ready: true,
  device: 'cpu',
  readyModels: 2,
  totalModels: 2,
  timestamp: DateTime.utc(2026, 8, 8),
);

AiModelsResponse _models({bool baseline = true, bool vmamba = true}) =>
    AiModelsResponse(
      requestId: 'm5-models-request',
      models: [
        AiModelInfo(
          key: 'YOLO26n-seg',
          name: 'YOLO26n-seg',
          family: 'baseline',
          ready: baseline,
        ),
        AiModelInfo(
          key: 'YOLO26n-VMamba-seg',
          name: 'YOLO26n-seg + VMamba',
          family: 'vmamba',
          ready: vmamba,
        ),
      ],
    );

Map<String, Object?> _modelResult({
  required String key,
  required String name,
  required String family,
  required bool detected,
  required double confidence,
  required int masks,
  required double time,
}) => {
  'modelKey': key,
  'modelName': name,
  'modelFamily': family,
  'detected': detected,
  'label': detected ? 'polyp' : null,
  'confidence': confidence,
  'maskCount': masks,
  'processingTimeMs': time,
  'overlay': {
    'mediaType': 'image/jpeg',
    'encoding': 'base64',
    'data': _jpegBase64,
  },
};

AiComparisonResult _result() => AiComparisonResult.fromJson({
  'requestId': 'm5-comparison-request',
  'originalFileName': 'comparison.png',
  'originalWidth': 1,
  'originalHeight': 1,
  'totalProcessingTimeMs': 104.5,
  'baseline': _modelResult(
    key: 'YOLO26n-seg',
    name: 'YOLO26n-seg',
    family: 'baseline',
    detected: true,
    confidence: 0.912,
    masks: 2,
    time: 43.5,
  ),
  'vmamba': _modelResult(
    key: 'YOLO26n-VMamba-seg',
    name: 'YOLO26n-seg + VMamba',
    family: 'vmamba',
    detected: false,
    confidence: 0.08,
    masks: 0,
    time: 61.0,
  ),
  'warning':
      'Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, không thay thế '
      'chẩn đoán hoặc quyết định chuyên môn của bác sĩ.',
});

typedef _CompareHandler =
    Future<AiComparisonResult> Function(
      AiImageUpload image,
      AiUploadProgress? progress,
      CancelToken? cancelToken,
    );

final class _FakeAiRepository implements AiRepository {
  AiModelsResponse models = _models();
  Object? modelsError;
  Future<AiModelsResponse> Function()? onModels;
  _CompareHandler? onCompare;
  int healthCalls = 0;
  int modelCalls = 0;
  int inferCalls = 0;
  int compareCalls = 0;
  AiImageUpload? lastImage;
  CancelToken? lastCancelToken;

  @override
  Future<AiHealthResponse> getHealth() async {
    healthCalls++;
    return _health();
  }

  @override
  Future<AiModelsResponse> getModels() async {
    modelCalls++;
    final error = modelsError;
    if (error != null) throw error;
    return onModels?.call() ?? models;
  }

  @override
  Future<AiInferenceResult> infer({
    required AiImageUpload image,
    required String modelKey,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) {
    inferCalls++;
    throw StateError('M5 comparison must not call inference');
  }

  @override
  Future<AiComparisonResult> compare({
    required AiImageUpload image,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    compareCalls++;
    lastImage = image;
    lastCancelToken = cancelToken;
    final handler = onCompare;
    if (handler != null) return handler(image, onSendProgress, cancelToken);
    onSendProgress?.call(50, 100);
    onSendProgress?.call(100, 100);
    return _result();
  }
}

final class _FakeImagePicker implements MedicalImagePicker {
  _FakeImagePicker(List<XFile?> files) : files = List.of(files);

  final List<XFile?> files;
  int calls = 0;

  @override
  Future<XFile?> pickFromGallery() async {
    calls++;
    return files.isEmpty ? null : files.removeAt(0);
  }
}

typedef _Harness = ({
  ProviderContainer container,
  _FakeAiRepository repository,
  _FakeImagePicker picker,
});

Future<_Harness> _pumpComparison(
  WidgetTester tester, {
  _FakeAiRepository? repository,
  _FakeImagePicker? picker,
  Size size = const Size(390, 3200),
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
  final repo = repository ?? _FakeAiRepository();
  final imagePicker = picker ?? _FakeImagePicker([_pngFile()]);
  final container = ProviderContainer(
    overrides: [
      aiServiceConfigProvider.overrideWithValue(
        AiServiceConfig.fromValue('http://10.0.2.2:8000', isRelease: false),
      ),
      directAiRepositoryProvider.overrideWithValue(repo),
      directComparisonImagePickerProvider.overrideWithValue(imagePicker),
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
  container.read(directAiRouterProvider).go(DirectAiRoutes.compare);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return (container: container, repository: repo, picker: imagePicker);
}

Future<void> _pickImage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('direct-comparison-pick-image')));
  await tester.pumpAndSettle();
}

Future<void> _pickAndCompare(WidgetTester tester) async {
  await _pickImage(tester);
  await tester.tap(find.byKey(const Key('direct-compare-button')));
  await tester.pumpAndSettle();
}

void main() {
  group('M5 shared image flow', () {
    test('1 shared validator accepts JPG', () async {
      final image = await MedicalImageValidator.validate(_jpegFile());
      expect(image.mimeType, 'image/jpeg');
      expect((image.width, image.height), (1, 1));
    });

    test('2 shared validator accepts PNG', () async {
      final image = await MedicalImageValidator.validate(_pngFile());
      expect(image.mimeType, 'image/png');
      expect((image.width, image.height), (1, 1));
    });

    test('3 rejects an empty image', () async {
      await expectLater(
        MedicalImageValidator.validate(
          XFile.fromData(Uint8List(0), path: 'empty.jpg'),
        ),
        throwsA(
          isA<MedicalImageValidationException>().having(
            (error) => error.message,
            'message',
            'Tệp ảnh không hợp lệ.',
          ),
        ),
      );
    });

    test('4 rejects an image larger than 10 MB', () async {
      await expectLater(
        MedicalImageValidator.validate(
          XFile.fromData(
            Uint8List(maxMedicalImageBytes + 1),
            path: 'large.png',
            mimeType: 'image/png',
          ),
        ),
        throwsA(
          isA<MedicalImageValidationException>().having(
            (error) => error.message,
            'message',
            'Ảnh vượt quá dung lượng 10 MB.',
          ),
        ),
      );
    });

    test('5 rejects unsupported format', () async {
      await expectLater(
        MedicalImageValidator.validate(
          XFile.fromData(
            Uint8List.fromList([0x47, 0x49, 0x46]),
            path: 'image.gif',
            mimeType: 'image/gif',
          ),
        ),
        throwsA(isA<MedicalImageValidationException>()),
      );
    });

    testWidgets('6 preview shows filename, size and dimensions', (
      tester,
    ) async {
      await _pumpComparison(tester);
      await _pickImage(tester);
      expect(
        find.byKey(const Key('direct-comparison-image-preview')),
        findsOneWidget,
      );
      expect(find.text('comparison.png'), findsOneWidget);
      expect(find.textContaining('1 × 1 px'), findsOneWidget);
    });

    testWidgets('7 selecting another image clears the prior selection', (
      tester,
    ) async {
      await _pumpComparison(
        tester,
        picker: _FakeImagePicker([_pngFile(), _jpegFile('replacement.jpeg')]),
      );
      await _pickImage(tester);
      await _pickImage(tester);
      expect(find.text('replacement.jpeg'), findsOneWidget);
      expect(find.text('comparison.png'), findsNothing);
    });

    testWidgets('8 remove returns to empty state', (tester) async {
      await _pumpComparison(tester);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-comparison-remove-image')));
      await tester.pumpAndSettle();
      expect(find.text('Chưa chọn ảnh'), findsOneWidget);
    });

    testWidgets('9 image selection never starts comparison automatically', (
      tester,
    ) async {
      final harness = await _pumpComparison(tester);
      await _pickImage(tester);
      expect(harness.repository.compareCalls, 0);
      expect(harness.repository.inferCalls, 0);
    });
  });

  group('M5 models and request state', () {
    testWidgets('10 models loading keeps compare disabled', (tester) async {
      final completer = Completer<AiModelsResponse>();
      final repository = _FakeAiRepository()..onModels = () => completer.future;
      await _pumpComparison(tester, repository: repository, settle: false);
      expect(find.text('Đang tải hai mô hình…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('direct-compare-button')),
            )
            .onPressed,
        isNull,
      );
      completer.complete(repository.models);
      await tester.pumpAndSettle();
    });

    testWidgets('11 both models must be ready', (tester) async {
      final repository = _FakeAiRepository()..models = _models(vmamba: false);
      await _pumpComparison(tester, repository: repository);
      await _pickImage(tester);
      expect(
        find.byKey(const Key('direct-comparison-models-not-ready')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('direct-compare-button')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('12 models error can be retried', (tester) async {
      final repository = _FakeAiRepository()
        ..modelsError = const AiApiException(
          kind: AiFailureKind.connection,
          message: 'offline',
        );
      await _pumpComparison(tester, repository: repository);
      repository.modelsError = null;
      await tester.tap(find.byKey(const Key('comparison-models-retry')));
      await tester.pumpAndSettle();
      expect(repository.modelCalls, 2);
    });

    test('13 controller sends one local image to repository.compare', () async {
      final repository = _FakeAiRepository();
      final picker = _FakeImagePicker([_pngFile()]);
      final container = ProviderContainer(
        overrides: [
          directAiRepositoryProvider.overrideWithValue(repository),
          directComparisonImagePickerProvider.overrideWithValue(picker),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        directComparisonControllerProvider.notifier,
      );
      container.read(directComparisonControllerProvider);
      await controller.pickImage(bothModelsReady: true);
      await controller.compare(bothModelsReady: true);
      expect(repository.compareCalls, 1);
      expect(repository.inferCalls, 0);
      expect(repository.lastImage?.mimeType, 'image/png');
      expect(await repository.lastImage!.readBytes(), _pngBytes);
      expect(repository.lastCancelToken, isNotNull);
    });

    test(
      '14 source calls compare and never dispatches two inference requests',
      () {
        final source = File(
          'lib/features/comparison/direct_comparison_controller.dart',
        ).readAsStringSync();
        expect(
          RegExp(r'_repository\.compare\(').allMatches(source),
          hasLength(1),
        );
        expect(source, isNot(contains('_repository.infer(')));
        expect(source, isNot(contains('/api/v1/inference')));
        expect(source, isNot(contains('/api/v1/comparison')));
      },
    );

    testWidgets('15 upload progress changes to two-model processing', (
      tester,
    ) async {
      final completer = Completer<AiComparisonResult>();
      AiUploadProgress? progress;
      final repository = _FakeAiRepository()
        ..onCompare = (image, callback, token) {
          progress = callback;
          callback?.call(30, 100);
          return completer.future;
        };
      await _pumpComparison(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-compare-button')));
      await tester.pump();
      expect(find.textContaining('30%'), findsOneWidget);
      progress?.call(100, 100);
      await tester.pump();
      expect(find.text('Đang chạy hai mô hình'), findsOneWidget);
      expect(
        find.textContaining('lần lượt xử lý ảnh bằng Baseline và VMamba'),
        findsOneWidget,
      );
      completer.complete(_result());
      await tester.pumpAndSettle();
    });

    testWidgets('16 double submit is blocked', (tester) async {
      final completer = Completer<AiComparisonResult>();
      final repository = _FakeAiRepository()
        ..onCompare = (image, progress, token) => completer.future;
      final harness = await _pumpComparison(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-compare-button')));
      await tester.pump();
      await harness.container
          .read(directComparisonControllerProvider.notifier)
          .compare(bothModelsReady: true);
      expect(repository.compareCalls, 1);
      completer.complete(_result());
      await tester.pumpAndSettle();
    });

    testWidgets('17 active comparison can be cancelled', (tester) async {
      final completer = Completer<AiComparisonResult>();
      final repository = _FakeAiRepository()
        ..onCompare = (image, progress, token) => completer.future;
      final harness = await _pumpComparison(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-compare-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('direct-comparison-cancel')));
      await tester.pump();
      expect(repository.lastCancelToken?.isCancelled, isTrue);
      expect(
        harness.container.read(directComparisonControllerProvider).status,
        DirectComparisonStatus.cancelled,
      );
      expect(find.text('Yêu cầu đã được hủy.'), findsOneWidget);
      completer.complete(_result());
    });
  });

  group('M5 comparison result', () {
    testWidgets('18 parses and renders baseline fields', (tester) async {
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      expect(
        find.byKey(const Key('direct-baseline-result-panel')),
        findsOneWidget,
      );
      expect(find.text('YOLO26n-seg'), findsWidgets);
      expect(find.text('91.2%'), findsOneWidget);
      expect(find.text('43.5 ms'), findsOneWidget);
    });

    testWidgets('19 mobile segment renders VMamba fields separately', (
      tester,
    ) async {
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      await tester.tap(find.text('VMamba').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('direct-vmamba-result-panel')),
        findsOneWidget,
      );
      expect(find.text('YOLO26n-seg + VMamba'), findsWidgets);
      expect(find.text('8.0%'), findsOneWidget);
      expect(find.text('61.0 ms'), findsOneWidget);
    });

    testWidgets('20 tablet renders baseline and VMamba side by side', (
      tester,
    ) async {
      await _pumpComparison(tester, size: const Size(1024, 2600));
      await _pickAndCompare(tester);
      expect(
        find.byKey(const Key('direct-baseline-result-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('direct-vmamba-result-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('direct-comparison-model-segment')),
        findsNothing,
      );
    });

    testWidgets('21 result keeps original bytes and two decoded overlays', (
      tester,
    ) async {
      final harness = await _pumpComparison(tester);
      await _pickAndCompare(tester);
      final state = harness.container.read(directComparisonControllerProvider);
      expect(state.image?.bytes, _pngBytes);
      expect(state.result?.baseline.overlay.bytes, _jpegBytes);
      expect(state.result?.vmamba.overlay.bytes, _jpegBytes);
      final baseline = state.result!.baseline.overlay.bytes;
      final vmamba = state.result!.vmamba.overlay.bytes;
      await tester.pump();
      final rebuilt = harness.container.read(
        directComparisonControllerProvider,
      );
      expect(
        identical(rebuilt.result!.baseline.overlay.bytes, baseline),
        isTrue,
      );
      expect(identical(rebuilt.result!.vmamba.overlay.bytes, vmamba), isTrue);
    });

    testWidgets('22 common metadata is complete', (tester) async {
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      expect(find.text('104.5 ms'), findsOneWidget);
      expect(find.text('1 × 1 px'), findsOneWidget);
      expect(find.text('comparison.png'), findsWidgets);
    });

    testWidgets('23 detected state is independent for each model', (
      tester,
    ) async {
      await _pumpComparison(tester, size: const Size(1024, 2600));
      await _pickAndCompare(tester);
      expect(find.text('Đã phát hiện vùng nghi ngờ polyp.'), findsOneWidget);
      expect(
        find.text('Không phát hiện vùng polyp trong ảnh.'),
        findsOneWidget,
      );
    });

    testWidgets('24 confidence, masks and times use neutral labels', (
      tester,
    ) async {
      await _pumpComparison(tester, size: const Size(1024, 2600));
      await _pickAndCompare(tester);
      expect(find.text('Độ tin cậy của dự đoán'), findsNWidgets(2));
      expect(find.text('Số vùng phân đoạn'), findsNWidgets(2));
      expect(find.text('Thời gian xử lý'), findsNWidgets(2));
      expect(find.textContaining('Độ chính xác'), findsNothing);
      expect(find.textContaining('xác suất mắc bệnh'), findsNothing);
    });

    testWidgets('25 official disclaimer is preserved', (tester) async {
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      expect(find.textContaining('không thay thế chẩn đoán'), findsWidgets);
    });

    test('26 production UI contains no ranking or recommendation language', () {
      final source = File(
        'lib/features/comparison/model_comparison_screen.dart',
      ).readAsStringSync().toLowerCase();
      expect(source, isNot(contains('winner')));
      expect(source, isNot(contains('best model')));
      expect(source, isNot(contains('recommendation')));
      expect(source, isNot(contains('tốt hơn')));
      expect(source, isNot(contains('image.network')));
    });

    testWidgets('27 choosing another image clears both overlays', (
      tester,
    ) async {
      await _pumpComparison(
        tester,
        picker: _FakeImagePicker([_pngFile(), _jpegFile('another.jpg')]),
      );
      await _pickAndCompare(tester);
      await tester.tap(find.byKey(const Key('direct-comparison-pick-another')));
      await tester.pumpAndSettle();
      expect(find.text('another.jpg'), findsOneWidget);
      expect(
        find.byKey(const Key('direct-baseline-overlay-image')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('direct-vmamba-overlay-image')),
        findsNothing,
      );
    });
  });

  group('M5 fullscreen', () {
    testWidgets('28 opens original image fullscreen', (tester) async {
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      await tester.tap(
        find.byKey(const Key('direct-comparison-original-fullscreen')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fullscreen-memory-image')), findsOneWidget);
    });

    testWidgets('29 opens Baseline overlay fullscreen', (tester) async {
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      await tester.tap(find.byKey(const Key('direct-baseline-fullscreen')));
      await tester.pumpAndSettle();
      expect(find.text('Baseline · Overlay'), findsOneWidget);
    });

    testWidgets('30 opens VMamba overlay fullscreen', (tester) async {
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      await tester.tap(find.text('VMamba').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('direct-vmamba-fullscreen')));
      await tester.pumpAndSettle();
      expect(find.text('VMamba integration · Overlay'), findsOneWidget);
    });
  });

  group('M5 safe errors, retry and reset', () {
    final cases = <AiApiException, String>{
      const AiApiException(
        kind: AiFailureKind.server,
        code: 'INVALID_IMAGE',
        message: 'raw',
      ): 'Tệp ảnh không hợp lệ.',
      const AiApiException(
        kind: AiFailureKind.server,
        code: 'FILE_TOO_LARGE',
        message: 'raw',
      ): 'Ảnh vượt quá dung lượng 10 MB.',
      const AiApiException(
        kind: AiFailureKind.server,
        code: 'UNSUPPORTED_MEDIA_TYPE',
        message: 'raw',
      ): 'Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG.',
      const AiApiException(
        kind: AiFailureKind.server,
        code: 'MODEL_NOT_READY',
        message: 'raw',
      ): 'Mô hình hiện chưa sẵn sàng.',
      const AiApiException(
        kind: AiFailureKind.server,
        code: 'SERVICE_BUSY',
        message: 'raw',
      ): 'Dịch vụ AI đang bận, vui lòng thử lại.',
      const AiApiException(kind: AiFailureKind.timeout, message: 'raw'):
          'Quá thời gian xử lý, vui lòng thử lại.',
      const AiApiException(kind: AiFailureKind.connection, message: 'raw'):
          'Không thể kết nối dịch vụ AI.',
      const AiApiException(
        kind: AiFailureKind.server,
        code: 'INFERENCE_FAILED',
        message: 'raw',
      ): 'Không thể hoàn tất quá trình phân tích.',
      const AiApiException(
        kind: AiFailureKind.server,
        code: 'INTERNAL_ERROR',
        message: 'raw',
      ): 'Dịch vụ AI gặp lỗi nội bộ.',
      const AiApiException(kind: AiFailureKind.invalidResponse, message: 'raw'):
          'Dịch vụ AI trả về phản hồi không hợp lệ.',
    };

    for (final entry in cases.entries) {
      test('31 maps ${entry.key.code ?? entry.key.kind.name} safely', () {
        expect(aiUserErrorMessage(entry.key), entry.value);
        expect(aiUserErrorMessage(entry.key), isNot(contains('raw')));
      });
    }

    testWidgets('32 retry keeps image and uses a fresh request', (
      tester,
    ) async {
      var calls = 0;
      final tokens = <CancelToken?>[];
      final repository = _FakeAiRepository()
        ..onCompare = (image, progress, token) async {
          tokens.add(token);
          calls++;
          if (calls == 1) {
            throw const AiApiException(
              kind: AiFailureKind.connection,
              message: 'raw socket error',
            );
          }
          return _result();
        };
      final harness = await _pumpComparison(tester, repository: repository);
      await _pickAndCompare(tester);
      var state = harness.container.read(directComparisonControllerProvider);
      expect(state.image, isNotNull);
      expect(find.text('Không thể kết nối dịch vụ AI.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('direct-comparison-retry')));
      await tester.pumpAndSettle();
      state = harness.container.read(directComparisonControllerProvider);
      expect(state.status, DirectComparisonStatus.success);
      expect(repository.compareCalls, 2);
      expect(identical(tokens.first, tokens.last), isFalse);
    });

    testWidgets('33 cancel is not rendered as a server failure', (
      tester,
    ) async {
      final completer = Completer<AiComparisonResult>();
      final repository = _FakeAiRepository()
        ..onCompare = (image, progress, token) => completer.future;
      await _pumpComparison(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-compare-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('direct-comparison-cancel')));
      await tester.pump();
      expect(find.text('Yêu cầu đã được hủy.'), findsOneWidget);
      expect(find.textContaining('lỗi máy chủ'), findsNothing);
      completer.complete(_result());
    });

    testWidgets('34 reset clears image, result, error and progress', (
      tester,
    ) async {
      final repository = _FakeAiRepository()
        ..onCompare = (image, progress, token) async =>
            throw const AiApiException(
              kind: AiFailureKind.connection,
              message: 'raw',
            );
      final harness = await _pumpComparison(tester, repository: repository);
      await _pickAndCompare(tester);
      await tester.tap(find.byKey(const Key('direct-comparison-reset')));
      await tester.pumpAndSettle();
      final state = harness.container.read(directComparisonControllerProvider);
      expect(state.status, DirectComparisonStatus.idle);
      expect(state.image, isNull);
      expect(state.result, isNull);
      expect(state.message, isNull);
      expect(state.uploadProgress, 0);
    });
  });

  group('M5 responsive and accessibility', () {
    for (final size in const [
      Size(320, 568),
      Size(360, 800),
      Size(412, 915),
      Size(600, 960),
      Size(800, 1280),
      Size(1024, 768),
      Size(915, 412),
    ]) {
      testWidgets('35 comparison form has no overflow at $size', (
        tester,
      ) async {
        await _pumpComparison(tester, size: size);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('36 text scale 1.3 keeps actions visible', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpComparison(tester, size: const Size(360, 2200));
      expect(
        find.byKey(const Key('direct-comparison-pick-image')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('37 dark mode result smoke test', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      expect(
        find.byKey(const Key('direct-baseline-overlay-image')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('38 progress exposes semantics and cancel', (tester) async {
      final completer = Completer<AiComparisonResult>();
      final repository = _FakeAiRepository()
        ..onCompare = (image, progress, token) {
          progress?.call(45, 100);
          return completer.future;
        };
      await _pumpComparison(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-compare-button')));
      await tester.pump();
      final semantics = tester.getSemantics(
        find.byKey(const Key('direct-comparison-upload-progress')),
      );
      expect(semantics.label, contains('Đang tải ảnh lên để so sánh'));
      expect(semantics.value, '45%');
      expect(find.byKey(const Key('direct-comparison-cancel')), findsOneWidget);
      completer.complete(_result());
      await tester.pumpAndSettle();
    });

    testWidgets('39 errors are live regions', (tester) async {
      final repository = _FakeAiRepository()
        ..onCompare = (image, progress, token) async =>
            throw const AiApiException(
              kind: AiFailureKind.connection,
              message: 'raw',
            );
      await _pumpComparison(tester, repository: repository);
      await _pickAndCompare(tester);
      final semantics = tester.getSemantics(
        find.byKey(const Key('direct-comparison-error')),
      );
      expect(semantics.flagsCollection.isLiveRegion, isTrue);
    });

    testWidgets('40 mobile model segment has an accessibility label', (
      tester,
    ) async {
      await _pumpComparison(tester);
      await _pickAndCompare(tester);
      expect(
        find.bySemanticsLabel('Chọn kết quả mô hình để xem'),
        findsOneWidget,
      );
    });

    testWidgets('41 disabled compare has an adjacent reason', (tester) async {
      await _pumpComparison(tester);
      expect(
        find.byKey(const Key('comparison-disabled-reason')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('direct-compare-button')),
            )
            .onPressed,
        isNull,
      );
    });
  });
}
