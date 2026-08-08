import 'dart:convert';
import 'dart:typed_data';

import 'package:app_polyp/core/network/ai_request_id.dart';

const int maxAiOverlayBytes = 20 * 1024 * 1024;
const Set<String> supportedAiModelKeys = {'YOLO26n-seg', 'YOLO26n-VMamba-seg'};

final class AiHealthResponse {
  const AiHealthResponse({
    required this.requestId,
    required this.status,
    required this.service,
    required this.ready,
    required this.device,
    required this.readyModels,
    required this.totalModels,
    required this.timestamp,
  });

  factory AiHealthResponse.fromJson(Map<String, Object?> json) {
    final readyModels = _nonNegativeInt(json, 'readyModels');
    final totalModels = _nonNegativeInt(json, 'totalModels');
    if (readyModels > totalModels) {
      throw const FormatException('readyModels exceeds totalModels');
    }
    final rawTimestamp = _requiredString(json, 'timestamp');
    return AiHealthResponse(
      requestId: _requestId(json),
      status: _requiredString(json, 'status'),
      service: _requiredString(json, 'service'),
      ready: _requiredBool(json, 'ready'),
      device: _requiredString(json, 'device'),
      readyModels: readyModels,
      totalModels: totalModels,
      timestamp: DateTime.parse(rawTimestamp),
    );
  }

  final String requestId;
  final String status;
  final String service;
  final bool ready;
  final String device;
  final int readyModels;
  final int totalModels;
  final DateTime timestamp;
}

final class AiModelInfo {
  const AiModelInfo({
    required this.key,
    required this.name,
    required this.family,
    required this.ready,
  });

  factory AiModelInfo.fromJson(Map<String, Object?> json) => AiModelInfo(
    key: _requiredString(json, 'key'),
    name: _requiredString(json, 'name'),
    family: _requiredString(json, 'family'),
    ready: _requiredBool(json, 'ready'),
  );

  final String key;
  final String name;
  final String family;
  final bool ready;
}

final class AiModelsResponse {
  const AiModelsResponse({required this.requestId, required this.models});

  factory AiModelsResponse.fromJson(Map<String, Object?> json) {
    final rawModels = json['models'];
    if (rawModels is! List) {
      throw const FormatException('models must be a list');
    }
    final models = rawModels
        .map((item) => AiModelInfo.fromJson(_requiredMapValue(item, 'models')))
        .toList(growable: false);
    final keys = models.map((model) => model.key).toSet();
    if (models.length != supportedAiModelKeys.length ||
        keys.length != models.length ||
        !keys.containsAll(supportedAiModelKeys)) {
      throw const FormatException(
        'models must contain the two supported models',
      );
    }
    return AiModelsResponse(
      requestId: _requestId(json),
      models: List.unmodifiable(models),
    );
  }

  final String requestId;
  final List<AiModelInfo> models;
}

final class AiOverlay {
  const AiOverlay._({
    required this.mediaType,
    required this.encoding,
    required this.data,
    required this.bytes,
  });

  factory AiOverlay.fromJson(Map<String, Object?> json) {
    final mediaType = _requiredString(json, 'mediaType');
    final encoding = _requiredString(json, 'encoding');
    final data = _requiredString(json, 'data');
    if (mediaType != 'image/jpeg') {
      throw const FormatException('overlay mediaType must be image/jpeg');
    }
    if (encoding != 'base64') {
      throw const FormatException('overlay encoding must be base64');
    }
    return AiOverlay._(
      mediaType: mediaType,
      encoding: encoding,
      data: data,
      bytes: AiOverlayDecoder.decodeJpeg(data),
    );
  }

  final String mediaType;
  final String encoding;
  final String data;
  final Uint8List bytes;
}

abstract final class AiOverlayDecoder {
  static Uint8List decodeJpeg(
    String data, {
    int maxDecodedBytes = maxAiOverlayBytes,
  }) {
    if (data.isEmpty || data.startsWith('data:') || maxDecodedBytes < 3) {
      throw const FormatException('overlay Base64 is invalid');
    }
    final maxEncodedLength = ((maxDecodedBytes + 2) ~/ 3) * 4;
    if (data.length > maxEncodedLength) {
      throw const FormatException('overlay exceeds the decoded size limit');
    }
    late Uint8List bytes;
    try {
      bytes = base64Decode(data);
    } on FormatException {
      throw const FormatException('overlay Base64 is invalid');
    }
    if (bytes.length > maxDecodedBytes) {
      throw const FormatException('overlay exceeds the decoded size limit');
    }
    if (bytes.length < 3 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[2] != 0xff) {
      throw const FormatException('overlay is not a JPEG image');
    }
    return bytes;
  }
}

final class AiInferenceResult {
  const AiInferenceResult({
    required this.requestId,
    required this.modelKey,
    required this.modelName,
    required this.modelFamily,
    required this.detected,
    required this.label,
    required this.confidence,
    required this.maskCount,
    required this.processingTimeMs,
    required this.originalFileName,
    required this.originalWidth,
    required this.originalHeight,
    required this.overlay,
    required this.warning,
  });

  factory AiInferenceResult.fromJson(Map<String, Object?> json) {
    final result = _AiModelResultFields.fromJson(json);
    return AiInferenceResult(
      requestId: _requestId(json),
      modelKey: result.modelKey,
      modelName: result.modelName,
      modelFamily: result.modelFamily,
      detected: result.detected,
      label: result.label,
      confidence: result.confidence,
      maskCount: result.maskCount,
      processingTimeMs: result.processingTimeMs,
      originalFileName: _requiredString(json, 'originalFileName'),
      originalWidth: _positiveInt(json, 'originalWidth'),
      originalHeight: _positiveInt(json, 'originalHeight'),
      overlay: result.overlay,
      warning: _requiredString(json, 'warning'),
    );
  }

  final String requestId;
  final String modelKey;
  final String modelName;
  final String modelFamily;
  final bool detected;
  final String? label;
  final double confidence;
  final int maskCount;
  final double processingTimeMs;
  final String originalFileName;
  final int originalWidth;
  final int originalHeight;
  final AiOverlay overlay;
  final String warning;
}

final class AiComparisonModelResult {
  const AiComparisonModelResult({
    required this.modelKey,
    required this.modelName,
    required this.modelFamily,
    required this.detected,
    required this.label,
    required this.confidence,
    required this.maskCount,
    required this.processingTimeMs,
    required this.overlay,
  });

  factory AiComparisonModelResult.fromJson(Map<String, Object?> json) {
    final result = _AiModelResultFields.fromJson(json);
    return AiComparisonModelResult(
      modelKey: result.modelKey,
      modelName: result.modelName,
      modelFamily: result.modelFamily,
      detected: result.detected,
      label: result.label,
      confidence: result.confidence,
      maskCount: result.maskCount,
      processingTimeMs: result.processingTimeMs,
      overlay: result.overlay,
    );
  }

  final String modelKey;
  final String modelName;
  final String modelFamily;
  final bool detected;
  final String? label;
  final double confidence;
  final int maskCount;
  final double processingTimeMs;
  final AiOverlay overlay;
}

final class AiComparisonResult {
  const AiComparisonResult({
    required this.requestId,
    required this.originalFileName,
    required this.originalWidth,
    required this.originalHeight,
    required this.totalProcessingTimeMs,
    required this.baseline,
    required this.vmamba,
    required this.warning,
  });

  factory AiComparisonResult.fromJson(Map<String, Object?> json) {
    final baseline = AiComparisonModelResult.fromJson(
      _requiredMap(json, 'baseline'),
    );
    final vmamba = AiComparisonModelResult.fromJson(
      _requiredMap(json, 'vmamba'),
    );
    if (baseline.modelKey != 'YOLO26n-seg' ||
        vmamba.modelKey != 'YOLO26n-VMamba-seg') {
      throw const FormatException('comparison model positions are invalid');
    }
    return AiComparisonResult(
      requestId: _requestId(json),
      originalFileName: _requiredString(json, 'originalFileName'),
      originalWidth: _positiveInt(json, 'originalWidth'),
      originalHeight: _positiveInt(json, 'originalHeight'),
      totalProcessingTimeMs: _nonNegativeFiniteNumber(
        json,
        'totalProcessingTimeMs',
      ),
      baseline: baseline,
      vmamba: vmamba,
      warning: _requiredString(json, 'warning'),
    );
  }

  final String requestId;
  final String originalFileName;
  final int originalWidth;
  final int originalHeight;
  final double totalProcessingTimeMs;
  final AiComparisonModelResult baseline;
  final AiComparisonModelResult vmamba;
  final String warning;
}

final class _AiModelResultFields {
  const _AiModelResultFields({
    required this.modelKey,
    required this.modelName,
    required this.modelFamily,
    required this.detected,
    required this.label,
    required this.confidence,
    required this.maskCount,
    required this.processingTimeMs,
    required this.overlay,
  });

  factory _AiModelResultFields.fromJson(Map<String, Object?> json) {
    final rawLabel = json['label'];
    if (rawLabel != null && rawLabel is! String) {
      throw const FormatException('label must be a string or null');
    }
    final modelKey = _requiredString(json, 'modelKey');
    if (!supportedAiModelKeys.contains(modelKey)) {
      throw const FormatException('modelKey is not supported');
    }
    return _AiModelResultFields(
      modelKey: modelKey,
      modelName: _requiredString(json, 'modelName'),
      modelFamily: _requiredString(json, 'modelFamily'),
      detected: _requiredBool(json, 'detected'),
      label: rawLabel as String?,
      confidence: _confidence(json),
      maskCount: _nonNegativeInt(json, 'maskCount'),
      processingTimeMs: _nonNegativeFiniteNumber(json, 'processingTimeMs'),
      overlay: AiOverlay.fromJson(_requiredMap(json, 'overlay')),
    );
  }

  final String modelKey;
  final String modelName;
  final String modelFamily;
  final bool detected;
  final String? label;
  final double confidence;
  final int maskCount;
  final double processingTimeMs;
  final AiOverlay overlay;
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

String _requestId(Map<String, Object?> json) {
  final value = _requiredString(json, 'requestId');
  if (!AiRequestIdGenerator.isValid(value)) {
    throw const FormatException('requestId is invalid');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! bool) throw FormatException('$field must be a boolean');
  return value;
}

int _nonNegativeInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int || value < 0) {
    throw FormatException('$field must be a non-negative integer');
  }
  return value;
}

int _positiveInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int || value <= 0) {
    throw FormatException('$field must be a positive integer');
  }
  return value;
}

double _nonNegativeFiniteNumber(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is bool || value is! num) {
    throw FormatException('$field must be a number');
  }
  final number = value.toDouble();
  if (!number.isFinite || number < 0) {
    throw FormatException('$field must be a finite non-negative number');
  }
  return number;
}

double _confidence(Map<String, Object?> json) {
  final value = _nonNegativeFiniteNumber(json, 'confidence');
  if (value > 1) {
    throw const FormatException('confidence must be between 0 and 1');
  }
  return value;
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String field) =>
    _requiredMapValue(json[field], field);

Map<String, Object?> _requiredMapValue(Object? value, String field) {
  if (value is! Map) throw FormatException('$field must be an object');
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    throw FormatException('$field must have string keys');
  }
}
