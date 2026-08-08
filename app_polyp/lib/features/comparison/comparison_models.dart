class ComparisonModelResult {
  const ComparisonModelResult({
    required this.id,
    required this.modelType,
    required this.modelCategory,
    required this.detected,
    required this.label,
    required this.confidence,
    required this.maskCount,
    required this.processingTimeMs,
    required this.resultImageUrl,
  });

  factory ComparisonModelResult.fromJson(Map<String, dynamic> json) =>
      ComparisonModelResult(
        id: _string(json['id']),
        modelType: _string(json['modelType'], fallback: 'Không xác định'),
        modelCategory: _string(json['modelCategory'], fallback: 'UNKNOWN'),
        detected: json['detected'] == true,
        label: _nullableString(json['label']),
        confidence: _ratio(json['confidence']),
        maskCount: _integer(json['maskCount']),
        processingTimeMs: _number(json['processingTimeMs']),
        resultImageUrl: _string(json['resultImageUrl']),
      );

  final String id;
  final String modelType;
  final String modelCategory;
  final bool detected;
  final String? label;
  final double confidence;
  final int maskCount;
  final double processingTimeMs;
  final String resultImageUrl;
}

class ComparisonResult {
  const ComparisonResult({
    required this.comparisonGroupId,
    required this.fileName,
    required this.createdAt,
    required this.originalImageUrl,
    required this.baseline,
    required this.vmamba,
    required this.totalProcessingTimeMs,
    required this.metadataUrl,
  });

  factory ComparisonResult.fromJson(Map<String, dynamic> json) =>
      ComparisonResult(
        comparisonGroupId: _string(json['comparisonGroupId']),
        fileName: _string(json['fileName'], fallback: 'Ảnh nội soi'),
        createdAt: DateTime.tryParse(_string(json['createdAt'])),
        originalImageUrl: _string(json['originalImageUrl']),
        baseline: ComparisonModelResult.fromJson(_map(json['baseline'])),
        vmamba: ComparisonModelResult.fromJson(_map(json['vmamba'])),
        totalProcessingTimeMs: _number(json['totalProcessingTimeMs']),
        metadataUrl: _string(json['metadataUrl']),
      );

  final String comparisonGroupId;
  final String fileName;
  final DateTime? createdAt;
  final String originalImageUrl;
  final ComparisonModelResult baseline;
  final ComparisonModelResult vmamba;
  final double totalProcessingTimeMs;
  final String metadataUrl;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

String _string(Object? value, {String fallback = ''}) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

String? _nullableString(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

int _integer(Object? value) =>
    value is num && value.isFinite ? value.toInt().clamp(0, 1 << 53) : 0;

double _number(Object? value) => value is num && value.isFinite
    ? value.toDouble().clamp(0, double.maxFinite)
    : 0;

double _ratio(Object? value) => _number(value).clamp(0, 1);
