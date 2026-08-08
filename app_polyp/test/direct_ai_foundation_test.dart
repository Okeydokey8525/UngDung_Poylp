import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:app_polyp/core/config/ai_service_config.dart';
import 'package:app_polyp/core/config/app_config.dart';
import 'package:app_polyp/core/network/ai_api_exception.dart';
import 'package:app_polyp/core/network/ai_error_mapper.dart';
import 'package:app_polyp/core/network/ai_request_id.dart';
import 'package:app_polyp/core/network/direct_ai_client.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _jpegBytes = <int>[0xff, 0xd8, 0xff, 0xd9];
final _jpegBase64 = base64Encode(_jpegBytes);

Map<String, Object?> healthJson({Map<String, Object?> extra = const {}}) => {
  'requestId': 'request-health',
  'status': 'ok',
  'service': 'PolypVision AI Service',
  'ready': true,
  'device': 'cpu',
  'readyModels': 2,
  'totalModels': 2,
  'timestamp': '2026-08-05T08:30:00Z',
  ...extra,
};

Map<String, Object?> modelsJson({Object? models}) => {
  'requestId': 'request-models',
  'models':
      models ??
      [
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
};

Map<String, Object?> modelResultJson({
  String modelKey = 'YOLO26n-seg',
  String family = 'baseline',
  bool detected = true,
  Object? confidence = 0.87,
  Object? maskCount = 2,
  Object? processingTimeMs = 42.5,
  Object? overlay,
}) => {
  'modelKey': modelKey,
  'modelName': modelKey,
  'modelFamily': family,
  'detected': detected,
  'label': detected ? 'polyp' : null,
  'confidence': confidence,
  'maskCount': maskCount,
  'processingTimeMs': processingTimeMs,
  'overlay':
      overlay ??
      {'mediaType': 'image/jpeg', 'encoding': 'base64', 'data': _jpegBase64},
};

Map<String, Object?> inferenceJson({
  bool detected = true,
  Object? confidence = 0.87,
  Object? maskCount = 2,
  Object? processingTimeMs = 42.5,
  Object? overlay,
  Object? width = 13,
  Object? height = 7,
}) => {
  'requestId': 'request-inference',
  ...modelResultJson(
    detected: detected,
    confidence: confidence,
    maskCount: maskCount,
    processingTimeMs: processingTimeMs,
    overlay: overlay,
  ),
  'originalFileName': 'sample.jpg',
  'originalWidth': width,
  'originalHeight': height,
  'warning': 'Chỉ phục vụ nghiên cứu.',
};

Map<String, Object?> comparisonJson({Object? totalProcessingTimeMs = 90.0}) => {
  'requestId': 'request-comparison',
  'originalFileName': 'sample.jpg',
  'originalWidth': 13,
  'originalHeight': 7,
  'totalProcessingTimeMs': totalProcessingTimeMs,
  'baseline': modelResultJson(),
  'vmamba': modelResultJson(modelKey: 'YOLO26n-VMamba-seg', family: 'vmamba'),
  'warning': 'Chỉ phục vụ nghiên cứu.',
};

Map<String, Object?> errorJson(
  String code, {
  int status = 503,
  String message = 'raw detail must not be displayed',
}) => {
  'requestId': 'request-error',
  'status': status,
  'code': code,
  'message': message,
  'fieldErrors': <String, String>{'image': 'invalid'},
};

ResponseBody jsonBody(Object value, {int statusCode = 200}) =>
    ResponseBody.fromString(
      jsonEncode(value),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );

typedef _AdapterHandler = ResponseBody Function(RequestOptions request);

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler, {this.consumeRequest = false});

  final _AdapterHandler handler;
  final bool consumeRequest;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (consumeRequest && requestStream != null) {
      await requestStream.drain<void>();
    }
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

({DirectAiRepository repository, Dio dio, _RecordingAdapter adapter}) _setup(
  _AdapterHandler handler, {
  bool consumeRequest = false,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://10.0.2.2:8000',
      connectTimeout: const Duration(seconds: 10),
    ),
  );
  final adapter = _RecordingAdapter(handler, consumeRequest: consumeRequest);
  dio.httpClientAdapter = adapter;
  final client = DirectAiClient(dio, AiRequestIdGenerator(random: Random(7)));
  return (repository: DirectAiRepository(client), dio: dio, adapter: adapter);
}

DioException dioError(DioExceptionType type, {Object? data}) {
  final options = RequestOptions(path: '/api/v1/inference');
  return DioException(
    requestOptions: options,
    type: type,
    response: data == null
        ? null
        : Response<Object?>(
            requestOptions: options,
            statusCode: 503,
            data: data,
          ),
  );
}

AiImageUpload upload() => AiImageUpload(
  name: '..\\sample.jpg',
  mimeType: 'image/jpeg',
  sizeBytes: _jpegBytes.length,
  readBytes: () async => Uint8List.fromList(_jpegBytes),
);

void main() {
  group('AI service config', () {
    test('1 uses the explicit AI_BASE_URL environment key', () {
      expect(AiServiceConfig.environmentKey, 'AI_BASE_URL');
    });

    test('2 debug empty value defaults to emulator port 8000', () {
      expect(
        AiServiceConfig.fromValue('', isRelease: false).baseUrl,
        'http://10.0.2.2:8000',
      );
    });

    test('3 removes one trailing slash', () {
      expect(
        AiServiceConfig.fromValue(
          'http://192.168.1.20:8000/',
          isRelease: false,
        ).baseUrl,
        'http://192.168.1.20:8000',
      );
    });

    test('4 removes repeated trailing slashes', () {
      expect(
        AiServiceConfig.fromValue(
          'http://10.0.2.2:8000///',
          isRelease: false,
        ).baseUrl,
        'http://10.0.2.2:8000',
      );
    });

    test('5 rejects a relative URL', () {
      expect(
        () => AiServiceConfig.fromValue('/api', isRelease: false),
        throwsFormatException,
      );
    });

    test('6 rejects a non-HTTP scheme', () {
      expect(
        () => AiServiceConfig.fromValue('ftp://host/x', isRelease: false),
        throwsFormatException,
      );
    });

    test('7 rejects release HTTP', () {
      expect(
        () =>
            AiServiceConfig.fromValue('http://ai.example.com', isRelease: true),
        throwsFormatException,
      );
    });

    test('8 rejects a release development host', () {
      expect(
        () => AiServiceConfig.fromValue(
          'https://localhost:8000',
          isRelease: true,
        ),
        throwsFormatException,
      );
    });

    test('9 accepts a release HTTPS origin', () {
      expect(
        AiServiceConfig.fromValue(
          'https://ai.example.com/',
          isRelease: true,
        ).baseUrl,
        'https://ai.example.com',
      );
    });

    test('10 rejects credentials, query and fragment', () {
      for (final value in [
        'https://user:pass@ai.example.com',
        'https://ai.example.com?x=1',
        'https://ai.example.com#x',
      ]) {
        expect(
          () => AiServiceConfig.fromValue(value, isRelease: false),
          throwsFormatException,
        );
      }
    });

    test('11 does not confuse the direct and legacy default ports', () {
      expect(AiServiceConfig.debugDefaultAiBaseUrl, endsWith(':8000'));
      expect(AppConfig.debugDefaultApiBaseUrl, endsWith(':8080'));
    });
  });

  group('request IDs', () {
    test('12 generated request ID matches the M1 character contract', () {
      final id = AiRequestIdGenerator(random: Random(1)).next();
      expect(AiRequestIdGenerator.isValid(id), isTrue);
    });

    test('13 generated request ID has UUID v4 shape', () {
      final id = AiRequestIdGenerator(random: Random(2)).next();
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-')));
    });

    test('14 consecutive request IDs are unique', () {
      final generator = AiRequestIdGenerator(random: Random(3));
      expect(generator.next(), isNot(generator.next()));
    });

    test('15 invalid or overlong request IDs are rejected', () {
      expect(AiRequestIdGenerator.isValid('bad id'), isFalse);
      expect(AiRequestIdGenerator.isValid('x' * 65), isFalse);
    });
  });

  group('strict response parsing', () {
    test('16 parses a valid health response and timestamp', () {
      final result = AiHealthResponse.fromJson(healthJson());
      expect(result.readyModels, 2);
      expect(result.timestamp.isUtc, isTrue);
    });

    test('17 rejects impossible health readiness counts', () {
      expect(
        () => AiHealthResponse.fromJson(healthJson(extra: {'readyModels': 3})),
        throwsFormatException,
      );
    });

    test('18 rejects an invalid health timestamp', () {
      expect(
        () => AiHealthResponse.fromJson(
          healthJson(extra: {'timestamp': 'not-a-time'}),
        ),
        throwsFormatException,
      );
    });

    test('19 parses exactly the two M1 models', () {
      final result = AiModelsResponse.fromJson(modelsJson());
      expect(result.models.map((item) => item.key), supportedAiModelKeys);
    });

    test('20 rejects a missing supported model', () {
      final onlyOne = (modelsJson()['models']! as List).take(1).toList();
      expect(
        () => AiModelsResponse.fromJson(modelsJson(models: onlyOne)),
        throwsFormatException,
      );
    });

    test('21 rejects duplicate model keys', () {
      final first = (modelsJson()['models']! as List).first;
      expect(
        () => AiModelsResponse.fromJson(modelsJson(models: [first, first])),
        throwsFormatException,
      );
    });

    test('22 parses detected inference', () {
      final result = AiInferenceResult.fromJson(inferenceJson());
      expect(result.detected, isTrue);
      expect(result.label, 'polyp');
      expect(result.overlay.bytes, _jpegBytes);
    });

    test('23 parses non-detected inference', () {
      final result = AiInferenceResult.fromJson(
        inferenceJson(detected: false, confidence: 0.0, maskCount: 0),
      );
      expect(result.detected, isFalse);
      expect(result.label, isNull);
    });

    test('24 parses comparison without inventing a winner', () {
      final result = AiComparisonResult.fromJson(comparisonJson());
      expect(result.baseline.modelKey, 'YOLO26n-seg');
      expect(result.vmamba.modelKey, 'YOLO26n-VMamba-seg');
    });

    test('25 rejects NaN confidence', () {
      expect(
        () => AiInferenceResult.fromJson(inferenceJson(confidence: double.nan)),
        throwsFormatException,
      );
    });

    test('26 rejects infinite processing time', () {
      expect(
        () => AiInferenceResult.fromJson(
          inferenceJson(processingTimeMs: double.infinity),
        ),
        throwsFormatException,
      );
    });

    test('27 rejects confidence above one', () {
      expect(
        () => AiInferenceResult.fromJson(inferenceJson(confidence: 1.01)),
        throwsFormatException,
      );
    });

    test('28 rejects negative confidence', () {
      expect(
        () => AiInferenceResult.fromJson(inferenceJson(confidence: -0.1)),
        throwsFormatException,
      );
    });

    test('29 rejects negative mask count', () {
      expect(
        () => AiInferenceResult.fromJson(inferenceJson(maskCount: -1)),
        throwsFormatException,
      );
    });

    test('30 rejects zero width', () {
      expect(
        () => AiInferenceResult.fromJson(inferenceJson(width: 0)),
        throwsFormatException,
      );
    });

    test('31 rejects negative height', () {
      expect(
        () => AiInferenceResult.fromJson(inferenceJson(height: -2)),
        throwsFormatException,
      );
    });

    test('32 rejects malformed Base64', () {
      expect(() => AiOverlayDecoder.decodeJpeg('%%%'), throwsFormatException);
    });

    test('33 rejects non-JPEG decoded bytes', () {
      expect(
        () => AiOverlayDecoder.decodeJpeg(base64Encode([1, 2, 3, 4])),
        throwsFormatException,
      );
    });

    test('34 rejects a data URL instead of raw Base64', () {
      expect(
        () =>
            AiOverlayDecoder.decodeJpeg('data:image/jpeg;base64,$_jpegBase64'),
        throwsFormatException,
      );
    });

    test('35 rejects a non-JPEG media type', () {
      expect(
        () => AiOverlay.fromJson({
          'mediaType': 'image/png',
          'encoding': 'base64',
          'data': _jpegBase64,
        }),
        throwsFormatException,
      );
    });

    test('36 rejects a non-base64 encoding', () {
      expect(
        () => AiOverlay.fromJson({
          'mediaType': 'image/jpeg',
          'encoding': 'binary',
          'data': _jpegBase64,
        }),
        throwsFormatException,
      );
    });

    test('37 rejects overlay larger than the configured decode limit', () {
      expect(
        () => AiOverlayDecoder.decodeJpeg(_jpegBase64, maxDecodedBytes: 3),
        throwsFormatException,
      );
    });

    test('38 ignores additional response fields', () {
      final json = inferenceJson()..['futureField'] = {'safe': true};
      expect(AiInferenceResult.fromJson(json).modelKey, 'YOLO26n-seg');
    });

    test('39 reports a missing required field as invalid data', () {
      final json = inferenceJson()..remove('warning');
      expect(() => AiInferenceResult.fromJson(json), throwsFormatException);
    });

    test('40 rejects boolean values where numbers are required', () {
      expect(
        () => AiComparisonResult.fromJson(
          comparisonJson(totalProcessingTimeMs: true),
        ),
        throwsFormatException,
      );
    });

    test('40a rejects an invalid response request ID', () {
      final json = inferenceJson()..['requestId'] = 'bad id';
      expect(() => AiInferenceResult.fromJson(json), throwsFormatException);
    });

    test('40b rejects an unsupported inference model key', () {
      final json = inferenceJson()..['modelKey'] = 'unknown-model';
      expect(() => AiInferenceResult.fromJson(json), throwsFormatException);
    });

    test('40c rejects swapped comparison model positions', () {
      final json = comparisonJson();
      final baseline = json['baseline'];
      json['baseline'] = json['vmamba'];
      json['vmamba'] = baseline;
      expect(() => AiComparisonResult.fromJson(json), throwsFormatException);
    });
  });

  group('AI error mapping', () {
    test('41 parses an error envelope from Map', () {
      expect(
        AiErrorMapper.parseEnvelope(errorJson('INVALID_IMAGE'))?.code,
        'INVALID_IMAGE',
      );
    });

    test('42 parses an error envelope from JSON String', () {
      expect(
        AiErrorMapper.parseEnvelope(jsonEncode(errorJson('TIMEOUT')))?.code,
        'TIMEOUT',
      );
    });

    test('43 parses an error envelope from JSON bytes', () {
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(errorJson('SERVICE_BUSY'))),
      );
      expect(AiErrorMapper.parseEnvelope(bytes)?.code, 'SERVICE_BUSY');
    });

    test('44 rejects a malformed error envelope safely', () {
      expect(AiErrorMapper.parseEnvelope('{broken'), isNull);
      expect(AiErrorMapper.parseEnvelope({'code': 1}), isNull);
      expect(AiErrorMapper.parseEnvelope({1: 'not-string-key'}), isNull);
    });

    for (final entry in <(DioExceptionType, AiFailureKind)>[
      (DioExceptionType.connectionError, AiFailureKind.connection),
      (DioExceptionType.connectionTimeout, AiFailureKind.timeout),
      (DioExceptionType.sendTimeout, AiFailureKind.timeout),
      (DioExceptionType.receiveTimeout, AiFailureKind.timeout),
      (DioExceptionType.transformTimeout, AiFailureKind.timeout),
      (DioExceptionType.cancel, AiFailureKind.cancelled),
      (DioExceptionType.unknown, AiFailureKind.connection),
    ].indexed) {
      test('${45 + entry.$1} maps Dio ${entry.$2.$1.name}', () {
        final mapped = AiErrorMapper.fromDio(dioError(entry.$2.$1));
        expect(mapped.kind, entry.$2.$2);
        expect(mapped.toString(), isNot(contains('DioException')));
      });
    }

    for (final entry in <(String, String)>[
      ('SERVICE_BUSY', 'đang bận'),
      ('MODEL_NOT_READY', 'chưa sẵn sàng'),
      ('INVALID_IMAGE', 'không hợp lệ'),
      ('FILE_TOO_LARGE', 'dung lượng'),
      ('UNSUPPORTED_MEDIA_TYPE', 'không được hỗ trợ'),
    ].indexed) {
      test('${52 + entry.$1} maps ${entry.$2.$1} to a safe message', () {
        final mapped = AiErrorMapper.fromDio(
          dioError(DioExceptionType.badResponse, data: errorJson(entry.$2.$1)),
        );
        expect(mapped.code, entry.$2.$1);
        expect(mapped.message, contains(entry.$2.$2));
        expect(mapped.requestId, 'request-error');
      });
    }

    test('57 INTERNAL_ERROR never exposes the raw server detail', () {
      final mapped = AiErrorMapper.fromDio(
        dioError(
          DioExceptionType.badResponse,
          data: errorJson(
            'INTERNAL_ERROR',
            message: r'C:\secret\checkpoint.pt traceback',
          ),
        ),
      );
      expect(mapped.message, isNot(contains('checkpoint')));
      expect(mapped.message, isNot(contains('traceback')));
    });

    test('58 a non-JSON bad response becomes INVALID_RESPONSE', () {
      final mapped = AiErrorMapper.fromDio(
        dioError(DioExceptionType.badResponse, data: '<html>error</html>'),
      );
      expect(mapped.kind, AiFailureKind.invalidResponse);
      expect(mapped.code, 'INVALID_RESPONSE');
    });
  });

  group('direct client and repository', () {
    test('59 uses the dedicated FastAPI base URL and no interceptors', () {
      final fixture = _setup((_) => jsonBody(healthJson()));
      expect(fixture.dio.options.baseUrl, 'http://10.0.2.2:8000');
      expect(fixture.dio.options.baseUrl, isNot(contains(':8080')));
      expect(
        fixture.dio.interceptors.map((item) => item.runtimeType.toString()),
        everyElement(isNot(anyOf(contains('Cookie'), contains('Csrf')))),
      );
    });

    test('60 health uses the M1 path with no cookie or CSRF', () async {
      final fixture = _setup((_) => jsonBody(healthJson()));
      await fixture.repository.getHealth();
      final request = fixture.adapter.requests.single;
      expect(request.path, '/api/v1/health');
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );
      expect(
        request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('x-csrf-token')),
      );
    });

    test('61 models uses the M1 path', () async {
      final fixture = _setup((_) => jsonBody(modelsJson()));
      await fixture.repository.getModels();
      expect(fixture.adapter.requests.single.path, '/api/v1/models');
    });

    test(
      '61a parses the documented unavailable health body at HTTP 503',
      () async {
        final unavailable = healthJson(
          extra: {'status': 'unavailable', 'ready': false, 'readyModels': 0},
        );
        final fixture = _setup((_) => jsonBody(unavailable, statusCode: 503));
        final result = await fixture.repository.getHealth();
        expect(result.status, 'unavailable');
        expect(result.ready, isFalse);
      },
    );

    test('62 inference sends image and modelKey multipart fields', () async {
      final fixture = _setup((_) => jsonBody(inferenceJson()));
      await fixture.repository.infer(image: upload(), modelKey: 'YOLO26n-seg');
      final request = fixture.adapter.requests.single;
      final form = request.data! as FormData;
      expect(request.path, '/api/v1/inference');
      expect(form.files.map((entry) => entry.key), ['image']);
      expect(Map.fromEntries(form.fields)['modelKey'], 'YOLO26n-seg');
    });

    test('63 comparison multipart contains only image', () async {
      final fixture = _setup((_) => jsonBody(comparisonJson()));
      await fixture.repository.compare(image: upload());
      final request = fixture.adapter.requests.single;
      final form = request.data! as FormData;
      expect(request.path, '/api/v1/comparison');
      expect(form.files.map((entry) => entry.key), ['image']);
      expect(form.fields, isEmpty);
    });

    test('64 each request carries a valid unique X-Request-ID', () async {
      final fixture = _setup((request) {
        return request.path.endsWith('health')
            ? jsonBody(healthJson())
            : jsonBody(modelsJson());
      });
      await fixture.repository.getHealth();
      await fixture.repository.getModels();
      final ids = fixture.adapter.requests
          .map((request) => request.headers['X-Request-ID']! as String)
          .toList();
      expect(ids.every(AiRequestIdGenerator.isValid), isTrue);
      expect(ids.toSet(), hasLength(2));
    });

    test(
      '65 every direct request accepts JSON and sends no credentials',
      () async {
        final fixture = _setup((_) => jsonBody(healthJson()));
        await fixture.repository.getHealth();
        final headers = fixture.adapter.requests.single.headers;
        expect(headers[Headers.acceptHeader], 'application/json');
        expect(headers['withCredentials'], isNull);
        expect(headers['JSESSIONID'], isNull);
      },
    );

    test(
      '66 health timeout is shorter than inference and comparison',
      () async {
        final fixture = _setup((request) {
          if (request.path.endsWith('health')) return jsonBody(healthJson());
          if (request.path.endsWith('inference')) {
            return jsonBody(inferenceJson());
          }
          return jsonBody(comparisonJson());
        });
        await fixture.repository.getHealth();
        await fixture.repository.infer(
          image: upload(),
          modelKey: 'YOLO26n-seg',
        );
        await fixture.repository.compare(image: upload());
        final requests = fixture.adapter.requests;
        expect(requests[0].receiveTimeout, DirectAiClient.shortRequestTimeout);
        expect(requests[1].sendTimeout, DirectAiClient.inferenceSendTimeout);
        expect(
          requests[1].receiveTimeout,
          DirectAiClient.inferenceReceiveTimeout,
        );
        expect(requests[2].sendTimeout, DirectAiClient.comparisonSendTimeout);
        expect(
          requests[2].receiveTimeout,
          DirectAiClient.comparisonReceiveTimeout,
        );
      },
    );

    test(
      '67 repository maps malformed success JSON to a domain error',
      () async {
        final fixture = _setup((_) => jsonBody({'unexpected': true}));
        await expectLater(
          fixture.repository.getHealth(),
          throwsA(
            isA<AiApiException>().having(
              (error) => error.code,
              'code',
              'INVALID_RESPONSE',
            ),
          ),
        );
      },
    );

    test('68 repository maps a FastAPI error envelope', () async {
      final fixture = _setup(
        (_) => jsonBody(errorJson('MODEL_NOT_READY'), statusCode: 503),
      );
      await expectLater(
        fixture.repository.getModels(),
        throwsA(
          isA<AiApiException>().having(
            (error) => error.code,
            'code',
            'MODEL_NOT_READY',
          ),
        ),
      );
    });

    test('69 inference exposes upload progress', () async {
      final progress = <(int, int)>[];
      final fixture = _setup(
        (_) => jsonBody(inferenceJson()),
        consumeRequest: true,
      );
      await fixture.repository.infer(
        image: upload(),
        modelKey: 'YOLO26n-seg',
        onSendProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(progress, isNotEmpty);
      expect(progress.last.$1, progress.last.$2);
    });

    test('70 comparison exposes upload progress', () async {
      final progress = <(int, int)>[];
      final fixture = _setup(
        (_) => jsonBody(comparisonJson()),
        consumeRequest: true,
      );
      await fixture.repository.compare(
        image: upload(),
        onSendProgress: (sent, total) => progress.add((sent, total)),
      );
      expect(progress, isNotEmpty);
    });

    test('71 safe filename removes path and header characters', () async {
      final fixture = _setup((_) => jsonBody(inferenceJson()));
      final unsafe = AiImageUpload(
        name: '..\\bad\r\n".jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 4,
        readBytes: () async => Uint8List.fromList(_jpegBytes),
      );
      await fixture.repository.infer(image: unsafe, modelKey: 'YOLO26n-seg');
      final form = fixture.adapter.requests.single.data! as FormData;
      expect(form.files.single.value.filename, 'bad.jpg');
    });

    test(
      '72 direct requests never call Spring or authentication endpoints',
      () async {
        final fixture = _setup((request) {
          if (request.path.endsWith('health')) return jsonBody(healthJson());
          return jsonBody(modelsJson());
        });
        await fixture.repository.getHealth();
        await fixture.repository.getModels();
        final paths = fixture.adapter.requests
            .map((request) => request.path)
            .join();
        expect(paths, isNot(contains('/auth/')));
        expect(paths, isNot(contains('/me')));
        expect(paths, isNot(contains('8080')));
      },
    );
  });

  group('Riverpod foundation', () {
    test('73 config and Dio providers remain independently overridable', () {
      final config = AiServiceConfig.fromValue(
        'http://192.168.1.30:8000',
        isRelease: false,
      );
      final container = ProviderContainer(
        overrides: [aiServiceConfigProvider.overrideWithValue(config)],
      );
      addTearDown(container.dispose);
      expect(
        container.read(directAiDioProvider).options.baseUrl,
        config.baseUrl,
      );
      expect(
        container
            .read(directAiDioProvider)
            .interceptors
            .map((item) => item.runtimeType.toString()),
        everyElement(isNot(anyOf(contains('Cookie'), contains('Csrf')))),
      );
    });

    test('74 health provider exposes successful async data', () async {
      final repository = _FakeAiRepository();
      final container = ProviderContainer(
        overrides: [directAiRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final result = await container.read(aiHealthProvider.future);
      expect(result.ready, isTrue);
      expect(repository.healthCalls, 1);
    });

    test('75 health provider exposes domain errors', () async {
      final repository = _FakeAiRepository(
        error: const AiApiException(
          kind: AiFailureKind.connection,
          message: 'Không thể kết nối dịch vụ AI.',
        ),
      );
      final container = ProviderContainer(
        overrides: [directAiRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await expectLater(
        container.read(aiHealthProvider.future),
        throwsA(isA<AiApiException>()),
      );
    });

    test('76 health provider can be refreshed without polling', () async {
      final repository = _FakeAiRepository();
      final container = ProviderContainer(
        overrides: [directAiRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(aiHealthProvider.future);
      await container.refresh(aiHealthProvider.future);
      expect(repository.healthCalls, 2);
    });

    test('77 models provider exposes the two direct AI models', () async {
      final repository = _FakeAiRepository();
      final container = ProviderContainer(
        overrides: [directAiRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final result = await container.read(aiModelsProvider.future);
      expect(result.models, hasLength(2));
      expect(repository.modelCalls, 1);
    });
  });
}

final class _FakeAiRepository implements AiRepository {
  _FakeAiRepository({this.error});

  final AiApiException? error;
  int healthCalls = 0;
  int modelCalls = 0;

  @override
  Future<AiHealthResponse> getHealth() async {
    healthCalls++;
    if (error case final value?) throw value;
    return AiHealthResponse.fromJson(healthJson());
  }

  @override
  Future<AiModelsResponse> getModels() async {
    modelCalls++;
    if (error case final value?) throw value;
    return AiModelsResponse.fromJson(modelsJson());
  }

  @override
  Future<AiInferenceResult> infer({
    required AiImageUpload image,
    required String modelKey,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) => Future.value(AiInferenceResult.fromJson(inferenceJson()));

  @override
  Future<AiComparisonResult> compare({
    required AiImageUpload image,
    AiUploadProgress? onSendProgress,
    CancelToken? cancelToken,
  }) => Future.value(AiComparisonResult.fromJson(comparisonJson()));
}
