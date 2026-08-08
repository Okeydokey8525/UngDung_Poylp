import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app_polyp/app/polypvision_app.dart';
import 'package:app_polyp/core/config/ai_service_config.dart';
import 'package:app_polyp/core/network/ai_api_exception.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/analysis/direct_analysis_controller.dart';
import 'package:app_polyp/features/analysis/direct_analysis_state.dart';
import 'package:app_polyp/navigation/direct_ai_router.dart';
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

XFile _pngFile([String name = 'polyp.png']) =>
    XFile.fromData(_pngBytes, path: name, mimeType: 'image/png');

XFile _jpegFile([String name = 'polyp.jpg']) =>
    XFile.fromData(_jpegBytes, path: name, mimeType: 'image/jpeg');

AiHealthResponse _health() => AiHealthResponse(
  requestId: 'm4-health-request',
  status: 'ok',
  service: 'PolypVision AI Service',
  ready: true,
  device: 'cpu',
  readyModels: 2,
  totalModels: 2,
  timestamp: DateTime.utc(2026, 8, 5),
);

AiModelsResponse _models({bool baseline = true, bool vmamba = true}) =>
    AiModelsResponse(
      requestId: 'm4-models-request',
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

AiInferenceResult _result({bool detected = true}) =>
    AiInferenceResult.fromJson({
      'requestId': 'm4-inference-request',
      'modelKey': 'YOLO26n-seg',
      'modelName': 'YOLO26n-seg',
      'modelFamily': 'baseline',
      'detected': detected,
      'label': detected ? 'polyp' : null,
      'confidence': detected ? 0.934 : 0.0,
      'maskCount': detected ? 2 : 0,
      'processingTimeMs': 148.5,
      'originalFileName': 'polyp.png',
      'originalWidth': 1,
      'originalHeight': 1,
      'overlay': {
        'mediaType': 'image/jpeg',
        'encoding': 'base64',
        'data': _jpegBase64,
      },
      'warning':
          'Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, không thay thế '
          'chẩn đoán hoặc quyết định chuyên môn của bác sĩ.',
    });

typedef _InferHandler =
    Future<AiInferenceResult> Function(
      AiImageUpload image,
      String modelKey,
      AiUploadProgress? progress,
      CancelToken? cancelToken,
    );

final class _FakeAiRepository implements AiRepository {
  AiModelsResponse models = _models();
  Object? modelsError;
  Future<AiModelsResponse> Function()? onModels;
  _InferHandler? onInfer;
  int healthCalls = 0;
  int modelCalls = 0;
  int inferCalls = 0;
  int compareCalls = 0;
  AiImageUpload? lastImage;
  String? lastModelKey;
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
    final handler = onModels;
    return handler == null ? models : handler();
  }

  @override
  Future<AiInferenceResult> infer({
    required AiImageUpload image,
    required String modelKey,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    inferCalls++;
    lastImage = image;
    lastModelKey = modelKey;
    lastCancelToken = cancelToken;
    final handler = onInfer;
    if (handler != null) {
      return handler(image, modelKey, onSendProgress, cancelToken);
    }
    onSendProgress?.call(50, 100);
    onSendProgress?.call(100, 100);
    return _result();
  }

  @override
  Future<AiComparisonResult> compare({
    required AiImageUpload image,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) {
    compareCalls++;
    throw StateError('M4 must not call comparison');
  }
}

final class _FakeImagePicker implements DirectAnalysisImagePicker {
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

Future<_Harness> _pumpAnalyze(
  WidgetTester tester, {
  _FakeAiRepository? repository,
  _FakeImagePicker? picker,
  Size size = const Size(390, 2600),
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
      directAnalysisImagePickerProvider.overrideWithValue(imagePicker),
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
  container.read(directAiRouterProvider).go(DirectAiRoutes.analyze);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return (container: container, repository: repo, picker: imagePicker);
}

Future<void> _pickImage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('direct-analysis-pick-image')));
  await tester.pumpAndSettle();
}

Future<void> _pickAndAnalyze(WidgetTester tester) async {
  await _pickImage(tester);
  await tester.tap(find.byKey(const Key('direct-analyze-button')));
  await tester.pumpAndSettle();
}

void main() {
  group('M4 image validation and selection', () {
    test('1 accepts a JPEG after checking its bytes and dimensions', () async {
      final image = await DirectImageValidator.validate(_jpegFile());
      expect(image.mimeType, 'image/jpeg');
      expect(image.width, 1);
      expect(image.height, 1);
    });

    test('2 accepts a PNG after checking its bytes and dimensions', () async {
      final image = await DirectImageValidator.validate(_pngFile());
      expect(image.mimeType, 'image/png');
      expect(image.width, 1);
      expect(image.height, 1);
    });

    test('3 rejects an empty file', () async {
      final file = XFile.fromData(Uint8List(0), path: 'empty.jpg');
      await expectLater(
        DirectImageValidator.validate(file),
        throwsA(
          isA<DirectImageValidationException>().having(
            (error) => error.message,
            'message',
            'Tệp ảnh không hợp lệ.',
          ),
        ),
      );
    });

    test('4 rejects a file larger than 10 MB before inference', () async {
      final file = XFile.fromData(
        Uint8List(maxDirectAnalysisImageBytes + 1),
        path: 'large.png',
        mimeType: 'image/png',
      );
      await expectLater(
        DirectImageValidator.validate(file),
        throwsA(
          isA<DirectImageValidationException>().having(
            (error) => error.message,
            'message',
            'Ảnh vượt quá dung lượng 10 MB.',
          ),
        ),
      );
    });

    test('5 rejects unsupported extension and MIME', () async {
      final file = XFile.fromData(
        Uint8List.fromList([0x47, 0x49, 0x46]),
        path: 'image.gif',
        mimeType: 'image/gif',
      );
      await expectLater(
        DirectImageValidator.validate(file),
        throwsA(isA<DirectImageValidationException>()),
      );
    });

    test('6 rejects extension that does not match image content', () async {
      await expectLater(
        DirectImageValidator.validate(_pngFile('renamed.jpg')),
        throwsA(isA<DirectImageValidationException>()),
      );
    });

    testWidgets('7 preview shows filename, size and dimensions', (
      tester,
    ) async {
      await _pumpAnalyze(tester);
      await _pickImage(tester);
      expect(
        find.byKey(const Key('direct-selected-image-preview')),
        findsOneWidget,
      );
      expect(find.text('polyp.png'), findsOneWidget);
      expect(find.textContaining('1 × 1 px'), findsOneWidget);
    });

    testWidgets('8 selecting again replaces the image and clears old state', (
      tester,
    ) async {
      await _pumpAnalyze(
        tester,
        picker: _FakeImagePicker([_pngFile(), _jpegFile('second.jpeg')]),
      );
      await _pickImage(tester);
      await _pickImage(tester);
      expect(find.text('second.jpeg'), findsOneWidget);
      expect(find.text('polyp.png'), findsNothing);
    });

    testWidgets('9 removing an image returns to the empty selection state', (
      tester,
    ) async {
      await _pumpAnalyze(tester);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-analysis-remove-image')));
      await tester.pumpAndSettle();
      expect(find.text('Chưa chọn ảnh'), findsOneWidget);
    });

    testWidgets('10 selecting an image never uploads automatically', (
      tester,
    ) async {
      final harness = await _pumpAnalyze(tester);
      await _pickImage(tester);
      expect(harness.repository.inferCalls, 0);
    });
  });

  group('M4 model selection', () {
    testWidgets('11 model loading is explicit and analysis remains disabled', (
      tester,
    ) async {
      final completer = Completer<AiModelsResponse>();
      final repository = _FakeAiRepository()..onModels = () => completer.future;
      await _pumpAnalyze(tester, repository: repository, settle: false);
      expect(find.text('Đang tải mô hình…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('direct-analyze-button')),
            )
            .onPressed,
        isNull,
      );
      completer.complete(repository.models);
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(2));
    });
    testWidgets('12 only ready models are selectable', (tester) async {
      final repository = _FakeAiRepository()..models = _models(vmamba: false);
      await _pumpAnalyze(tester, repository: repository);
      final baseline = tester.widget<ChoiceChip>(
        find.byKey(const Key('analysis-model-YOLO26n-seg')),
      );
      final vmamba = tester.widget<ChoiceChip>(
        find.byKey(const Key('analysis-model-YOLO26n-VMamba-seg')),
      );
      expect(baseline.onSelected, isNotNull);
      expect(vmamba.onSelected, isNull);
    });

    testWidgets('13 no ready model shows a retry and blocks submission', (
      tester,
    ) async {
      final repository = _FakeAiRepository()
        ..models = _models(baseline: false, vmamba: false);
      await _pumpAnalyze(tester, repository: repository);
      await _pickImage(tester);
      expect(
        find.byKey(const Key('direct-analysis-no-ready-model')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('direct-analyze-button')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('14 model provider error can be retried', (tester) async {
      final repository = _FakeAiRepository()
        ..modelsError = const AiApiException(
          kind: AiFailureKind.connection,
          message: 'offline',
        );
      await _pumpAnalyze(tester, repository: repository);
      repository.modelsError = null;
      await tester.tap(find.byKey(const Key('analysis-models-retry')));
      await tester.pumpAndSettle();
      expect(repository.modelCalls, 2);
      expect(find.byType(ChoiceChip), findsNWidgets(2));
    });

    testWidgets('15 a selected model becoming unavailable blocks submit', (
      tester,
    ) async {
      final harness = await _pumpAnalyze(tester);
      await _pickImage(tester);
      harness.repository.models = _models(baseline: false, vmamba: true);
      harness.container.invalidate(aiModelsProvider);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('direct-analyze-button')),
            )
            .onPressed,
        isNull,
      );
      expect(harness.repository.inferCalls, 0);
    });
  });

  group('M4 inference state and lifecycle', () {
    test(
      '16 controller sends selected image and model to direct repository',
      () async {
        final repository = _FakeAiRepository();
        final picker = _FakeImagePicker([_pngFile()]);
        final container = ProviderContainer(
          overrides: [
            directAiRepositoryProvider.overrideWithValue(repository),
            directAnalysisImagePickerProvider.overrideWithValue(picker),
          ],
        );
        addTearDown(container.dispose);
        final controller = container.read(
          directAnalysisControllerProvider.notifier,
        );
        container.read(directAnalysisControllerProvider);
        controller.synchronizeModels(_models().models);
        await controller.pickImage();
        await controller.analyze(
          readyModelKeys: const {'YOLO26n-seg', 'YOLO26n-VMamba-seg'},
        );
        expect(repository.lastModelKey, 'YOLO26n-seg');
        expect(repository.lastImage?.mimeType, 'image/png');
        expect(await repository.lastImage!.readBytes(), _pngBytes);
        expect(repository.lastCancelToken, isNotNull);
      },
    );

    testWidgets('17 upload progress transitions to indeterminate processing', (
      tester,
    ) async {
      final completer = Completer<AiInferenceResult>();
      AiUploadProgress? progress;
      final repository = _FakeAiRepository()
        ..onInfer = (image, model, callback, token) {
          progress = callback;
          callback?.call(25, 100);
          return completer.future;
        };
      await _pumpAnalyze(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-analyze-button')));
      await tester.pump();
      expect(
        find.byKey(const Key('direct-inference-upload-progress')),
        findsOneWidget,
      );
      expect(find.textContaining('25%'), findsOneWidget);
      progress?.call(100, 100);
      await tester.pump();
      expect(
        find.byKey(const Key('direct-inference-processing')),
        findsOneWidget,
      );
      completer.complete(_result());
      await tester.pumpAndSettle();
    });

    testWidgets('18 double submit is blocked while a request is active', (
      tester,
    ) async {
      final completer = Completer<AiInferenceResult>();
      final repository = _FakeAiRepository()
        ..onInfer = (image, model, progress, token) => completer.future;
      final harness = await _pumpAnalyze(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-analyze-button')));
      await tester.pump();
      await harness.container
          .read(directAnalysisControllerProvider.notifier)
          .analyze(readyModelKeys: const {'YOLO26n-seg'});
      expect(repository.inferCalls, 1);
      completer.complete(_result());
      await tester.pumpAndSettle();
    });

    testWidgets('19 active inference can be cancelled', (tester) async {
      final completer = Completer<AiInferenceResult>();
      final repository = _FakeAiRepository()
        ..onInfer = (image, model, progress, token) => completer.future;
      final harness = await _pumpAnalyze(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-analyze-button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('direct-analysis-cancel')));
      await tester.pump();
      expect(repository.lastCancelToken?.isCancelled, isTrue);
      expect(
        harness.container.read(directAnalysisControllerProvider).status,
        DirectAnalysisStatus.cancelled,
      );
      expect(find.text('Yêu cầu đã được hủy.'), findsOneWidget);
      completer.complete(_result());
    });

    testWidgets('20 success detected true renders the cautious status', (
      tester,
    ) async {
      await _pumpAnalyze(tester);
      await _pickAndAnalyze(tester);
      expect(find.text('Đã phát hiện vùng nghi ngờ polyp'), findsOneWidget);
    });

    testWidgets('21 success detected false renders a non-diagnostic status', (
      tester,
    ) async {
      final repository = _FakeAiRepository()
        ..onInfer = (image, model, progress, token) async =>
            _result(detected: false);
      await _pumpAnalyze(tester, repository: repository);
      await _pickAndAnalyze(tester);
      expect(find.text('Không phát hiện vùng polyp trong ảnh'), findsOneWidget);
    });

    testWidgets(
      '22 result keeps the selected local image and decoded overlay',
      (tester) async {
        final harness = await _pumpAnalyze(tester);
        await _pickAndAnalyze(tester);
        final state = harness.container.read(directAnalysisControllerProvider);
        expect(state.image?.bytes, _pngBytes);
        expect(state.result?.overlay.bytes, _jpegBytes);
        final overlayReference = state.result!.overlay.bytes;
        await tester.pump();
        expect(
          identical(
            harness.container
                .read(directAnalysisControllerProvider)
                .result!
                .overlay
                .bytes,
            overlayReference,
          ),
          isTrue,
        );
      },
    );

    test('23 direct M4 source has no Image.network or Spring invalidation', () {
      final source = File(
        'lib/features/analysis/single_inference_screen.dart',
      ).readAsStringSync();
      final controller = File(
        'lib/features/analysis/direct_analysis_controller.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('Image.network')));
      expect(controller, isNot(contains('dashboardControllerProvider')));
      expect(controller, isNot(contains('diagnosisHistoryControllerProvider')));
      expect(controller, isNot(contains('/api/v1/')));
      expect(controller, isNot(contains('AuthState')));
    });
  });

  group('M4 result UI', () {
    testWidgets('24 metadata uses confidence semantics and complete fields', (
      tester,
    ) async {
      await _pumpAnalyze(tester);
      await _pickAndAnalyze(tester);
      expect(find.text('YOLO26n-seg'), findsWidgets);
      expect(find.text('Độ tin cậy của dự đoán'), findsOneWidget);
      expect(find.text('93.4%'), findsOneWidget);
      expect(find.textContaining('Độ chính xác'), findsNothing);
      expect(find.text('Số vùng mask'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('148.5 ms'), findsOneWidget);
      expect(find.text('1 × 1 px'), findsOneWidget);
      expect(find.text('polyp.png'), findsWidgets);
    });

    testWidgets('25 official disclaimer remains visible on the result', (
      tester,
    ) async {
      await _pumpAnalyze(tester);
      await _pickAndAnalyze(tester);
      expect(find.textContaining('không thay thế chẩn đoán'), findsWidgets);
    });

    testWidgets('26 original image opens and closes fullscreen', (
      tester,
    ) async {
      await _pumpAnalyze(tester);
      await _pickAndAnalyze(tester);
      await tester.tap(find.byKey(const Key('direct-original-fullscreen')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('fullscreen-memory-image')), findsOneWidget);
      expect(
        find.byKey(const Key('fullscreen-memory-interactive-viewer')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('fullscreen-memory-close')));
      await tester.pumpAndSettle();
    });

    testWidgets('27 overlay image opens fullscreen from memory bytes', (
      tester,
    ) async {
      await _pumpAnalyze(tester);
      await _pickAndAnalyze(tester);
      await tester.tap(find.byKey(const Key('direct-overlay-fullscreen')));
      await tester.pumpAndSettle();
      expect(find.text('Overlay phân đoạn'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('28 choosing another image clears the previous result', (
      tester,
    ) async {
      await _pumpAnalyze(
        tester,
        picker: _FakeImagePicker([_pngFile(), _jpegFile('another.jpg')]),
      );
      await _pickAndAnalyze(tester);
      await tester.tap(find.byKey(const Key('direct-analysis-pick-another')));
      await tester.pumpAndSettle();
      expect(find.text('another.jpg'), findsOneWidget);
      expect(
        find.byKey(const Key('direct-result-overlay-image')),
        findsNothing,
      );
    });
  });

  group('M4 safe errors and retry', () {
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
      const AiApiException(kind: AiFailureKind.invalidResponse, message: 'raw'):
          'Dịch vụ AI trả về phản hồi không hợp lệ.',
    };

    for (final entry in cases.entries) {
      test('29 maps ${entry.key.code ?? entry.key.kind.name} safely', () {
        expect(directAnalysisErrorMessage(entry.key), entry.value);
        expect(directAnalysisErrorMessage(entry.key), isNot(contains('raw')));
      });
    }

    testWidgets('30 retry keeps image and model, then succeeds', (
      tester,
    ) async {
      var calls = 0;
      final repository = _FakeAiRepository()
        ..onInfer = (image, model, progress, token) async {
          calls++;
          if (calls == 1) {
            throw const AiApiException(
              kind: AiFailureKind.connection,
              message: 'raw socket exception',
            );
          }
          return _result();
        };
      final harness = await _pumpAnalyze(tester, repository: repository);
      await _pickAndAnalyze(tester);
      var state = harness.container.read(directAnalysisControllerProvider);
      expect(state.image, isNotNull);
      expect(state.selectedModelKey, 'YOLO26n-seg');
      expect(find.text('Không thể kết nối dịch vụ AI.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('direct-analysis-retry')));
      await tester.pumpAndSettle();
      state = harness.container.read(directAnalysisControllerProvider);
      expect(state.status, DirectAnalysisStatus.success);
      expect(repository.inferCalls, 2);
    });

    testWidgets('31 reset clears an error and selected image', (tester) async {
      final repository = _FakeAiRepository()
        ..onInfer = (image, model, progress, token) async =>
            throw const AiApiException(
              kind: AiFailureKind.connection,
              message: 'raw',
            );
      final harness = await _pumpAnalyze(tester, repository: repository);
      await _pickAndAnalyze(tester);
      await tester.tap(find.byKey(const Key('direct-analysis-reset')));
      await tester.pumpAndSettle();
      final state = harness.container.read(directAnalysisControllerProvider);
      expect(state.image, isNull);
      expect(state.message, isNull);
      expect(state.status, DirectAnalysisStatus.idle);
    });
  });

  group('M4 responsive and accessibility', () {
    for (final size in const [
      Size(320, 1600),
      Size(412, 1800),
      Size(800, 1400),
      Size(1024, 900),
    ]) {
      testWidgets('32 Analyze has no overflow at ${size.width} px', (
        tester,
      ) async {
        await _pumpAnalyze(tester, size: size);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('33 text scale 1.3 keeps controls available', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpAnalyze(tester, size: const Size(360, 1800));
      expect(
        find.byKey(const Key('direct-analysis-pick-image')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('34 dark mode result is a safe smoke test', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await _pumpAnalyze(tester);
      await _pickAndAnalyze(tester);
      expect(
        find.byKey(const Key('direct-result-overlay-image')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('35 progress exposes semantics and a cancel action', (
      tester,
    ) async {
      final completer = Completer<AiInferenceResult>();
      final repository = _FakeAiRepository()
        ..onInfer = (image, model, progress, token) {
          progress?.call(40, 100);
          return completer.future;
        };
      await _pumpAnalyze(tester, repository: repository);
      await _pickImage(tester);
      await tester.tap(find.byKey(const Key('direct-analyze-button')));
      await tester.pump();
      final semantics = tester.getSemantics(
        find.byKey(const Key('direct-inference-upload-progress')),
      );
      expect(semantics.label, contains('Đang tải ảnh lên'));
      expect(semantics.value, '40%');
      expect(find.byKey(const Key('direct-analysis-cancel')), findsOneWidget);
      completer.complete(_result());
      await tester.pumpAndSettle();
    });

    testWidgets('36 error is a live region and disabled action has a reason', (
      tester,
    ) async {
      final repository = _FakeAiRepository()
        ..onInfer = (image, model, progress, token) async =>
            throw const AiApiException(
              kind: AiFailureKind.connection,
              message: 'raw',
            );
      await _pumpAnalyze(tester, repository: repository);
      expect(find.byKey(const Key('analysis-disabled-reason')), findsOneWidget);
      await _pickAndAnalyze(tester);
      final semantics = tester.getSemantics(
        find.byKey(const Key('direct-analysis-error')),
      );
      expect(semantics.flagsCollection.isLiveRegion, isTrue);
    });
  });
}
