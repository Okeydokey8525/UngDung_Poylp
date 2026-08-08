typedef JsonItemParser<T> = T Function(Map<String, dynamic> json);

class PagedResponse<T> {
  const PagedResponse({
    required this.items,
    required this.page,
    required this.size,
    required this.totalItems,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrevious,
  });

  factory PagedResponse.fromJson(
    Map<String, dynamic> json,
    JsonItemParser<T> parser,
  ) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) => parser(Map<String, dynamic>.from(item)))
              .toList(growable: false)
        : <T>[];
    return PagedResponse(
      items: items,
      page: _nonNegativeInt(json['page']),
      size: _positiveInt(json['size'], 10),
      totalItems: _nonNegativeInt(json['totalItems']),
      totalPages: _nonNegativeInt(json['totalPages']),
      hasNext: json['hasNext'] == true,
      hasPrevious: json['hasPrevious'] == true,
    );
  }

  final List<T> items;
  final int page;
  final int size;
  final int totalItems;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;
}

class DiagnosisHistoryItem {
  const DiagnosisHistoryItem({
    required this.id,
    required this.fileName,
    required this.modelType,
    required this.modelCategory,
    required this.detected,
    required this.label,
    required this.confidence,
    required this.maskCount,
    required this.processingTimeMs,
    required this.createdAt,
    required this.originalImageUrl,
    required this.resultImageUrl,
  });

  factory DiagnosisHistoryItem.fromJson(Map<String, dynamic> json) =>
      DiagnosisHistoryItem(
        id: _string(json['id']),
        fileName: _string(json['fileName'], fallback: 'Không rõ tên file'),
        modelType: _string(json['modelType'], fallback: 'Không xác định'),
        modelCategory: _string(json['modelCategory'], fallback: 'UNKNOWN'),
        detected: json['detected'] == true,
        label: _nullableString(json['label']),
        confidence: _ratio(json['confidence']),
        maskCount: _nonNegativeInt(json['maskCount']),
        processingTimeMs: _nonNegativeDouble(json['processingTimeMs']),
        createdAt: _date(json['createdAt']),
        originalImageUrl: _string(json['originalImageUrl']),
        resultImageUrl: _string(json['resultImageUrl']),
      );

  final String id;
  final String fileName;
  final String modelType;
  final String modelCategory;
  final bool detected;
  final String? label;
  final double confidence;
  final int maskCount;
  final double processingTimeMs;
  final DateTime? createdAt;
  final String originalImageUrl;
  final String resultImageUrl;
}

class ComparisonHistoryModelResult {
  const ComparisonHistoryModelResult({
    required this.id,
    required this.detected,
    required this.confidence,
    required this.maskCount,
    required this.processingTimeMs,
    required this.resultImageUrl,
  });

  factory ComparisonHistoryModelResult.fromJson(Map<String, dynamic> json) =>
      ComparisonHistoryModelResult(
        id: _string(json['id']),
        detected: json['detected'] == true,
        confidence: _ratio(json['confidence']),
        maskCount: _nonNegativeInt(json['maskCount']),
        processingTimeMs: _nonNegativeDouble(json['processingTimeMs']),
        resultImageUrl: _string(json['resultImageUrl']),
      );

  final String id;
  final bool detected;
  final double confidence;
  final int maskCount;
  final double processingTimeMs;
  final String resultImageUrl;
}

class ComparisonHistoryItem {
  const ComparisonHistoryItem({
    required this.comparisonGroupId,
    required this.fileName,
    required this.createdAt,
    required this.originalImageUrl,
    required this.baseline,
    required this.vmamba,
    required this.totalProcessingTimeMs,
  });

  factory ComparisonHistoryItem.fromJson(Map<String, dynamic> json) =>
      ComparisonHistoryItem(
        comparisonGroupId: _string(json['comparisonGroupId']),
        fileName: _string(json['fileName'], fallback: 'Không rõ tên file'),
        createdAt: _date(json['createdAt']),
        originalImageUrl: _string(json['originalImageUrl']),
        baseline: ComparisonHistoryModelResult.fromJson(_map(json['baseline'])),
        vmamba: ComparisonHistoryModelResult.fromJson(_map(json['vmamba'])),
        totalProcessingTimeMs: _nonNegativeDouble(
          json['totalProcessingTimeMs'],
        ),
      );

  final String comparisonGroupId;
  final String fileName;
  final DateTime? createdAt;
  final String originalImageUrl;
  final ComparisonHistoryModelResult baseline;
  final ComparisonHistoryModelResult vmamba;
  final double totalProcessingTimeMs;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  return parsed < 0 ? 0 : parsed;
}

int _positiveInt(Object? value, int fallback) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed == null || parsed <= 0 ? fallback : parsed;
}

double _nonNegativeDouble(Object? value) {
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  return parsed == null || !parsed.isFinite || parsed < 0 ? 0 : parsed;
}

double _ratio(Object? value) => _nonNegativeDouble(value).clamp(0, 1);

DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');
