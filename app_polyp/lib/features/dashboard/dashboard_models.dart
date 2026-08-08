enum RecentActivityType { diagnosis, comparison }

class DashboardSummary {
  const DashboardSummary({
    this.singleAnalysisCount = 0,
    this.comparisonSessionCount = 0,
    this.totalInferenceCount = 0,
    this.detectedCount = 0,
    this.notDetectedCount = 0,
    this.baselineCount = 0,
    this.vmambaCount = 0,
    this.averageProcessingTimeMs = 0,
    this.averageDetectedConfidence = 0,
    this.totalMaskCount = 0,
    this.detectedRate = 0,
    this.mostUsedModel,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      singleAnalysisCount: _safeInt(json['singleAnalysisCount']),
      comparisonSessionCount: _safeInt(json['comparisonSessionCount']),
      totalInferenceCount: _safeInt(json['totalInferenceCount']),
      detectedCount: _safeInt(json['detectedCount']),
      notDetectedCount: _safeInt(json['notDetectedCount']),
      baselineCount: _safeInt(json['baselineCount']),
      vmambaCount: _safeInt(json['vmambaCount']),
      averageProcessingTimeMs: _safeDouble(json['averageProcessingTimeMs']),
      averageDetectedConfidence: _ratio(json['averageDetectedConfidence']),
      totalMaskCount: _safeInt(json['totalMaskCount']),
      detectedRate: _ratio(json['detectedRate']),
      mostUsedModel: _nullableString(json['mostUsedModel']),
    );
  }

  final int singleAnalysisCount;
  final int comparisonSessionCount;
  final int totalInferenceCount;
  final int detectedCount;
  final int notDetectedCount;
  final int baselineCount;
  final int vmambaCount;
  final double averageProcessingTimeMs;
  final double averageDetectedConfidence;
  final int totalMaskCount;
  final double detectedRate;
  final String? mostUsedModel;
}

class DailyUsage {
  const DailyUsage({required this.date, required this.count});

  factory DailyUsage.fromJson(Map<String, dynamic> json) {
    return DailyUsage(
      date:
          DateTime.tryParse(_safeString(json['date'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      count: _safeInt(json['count']),
    );
  }

  final DateTime date;
  final int count;
}

class ModelUsage {
  const ModelUsage({this.baseline = 0, this.vmamba = 0});

  factory ModelUsage.fromJson(Map<String, dynamic> json) => ModelUsage(
    baseline: _safeInt(json['baseline']),
    vmamba: _safeInt(json['vmamba']),
  );

  final int baseline;
  final int vmamba;
  int get total => baseline + vmamba;
}

class PredictionUsage {
  const PredictionUsage({this.detected = 0, this.notDetected = 0});

  factory PredictionUsage.fromJson(Map<String, dynamic> json) =>
      PredictionUsage(
        detected: _safeInt(json['detected']),
        notDetected: _safeInt(json['notDetected']),
      );

  final int detected;
  final int notDetected;
  int get total => detected + notDetected;
}

class RecentActivity {
  const RecentActivity({
    required this.id,
    required this.type,
    required this.fileName,
    required this.modelType,
    required this.detected,
    required this.confidence,
    required this.maskCount,
    required this.processingTimeMs,
    required this.createdAt,
    this.comparisonGroupId,
    this.originalImageUrl,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    final rawType = _safeString(json['type']).toUpperCase();
    return RecentActivity(
      id: _safeString(json['id']),
      type: rawType == 'COMPARISON'
          ? RecentActivityType.comparison
          : RecentActivityType.diagnosis,
      fileName: _safeString(json['fileName'], fallback: 'Không rõ tên ảnh'),
      modelType: _safeString(json['modelType'], fallback: 'Không xác định'),
      detected: json['detected'] == true,
      confidence: _ratio(json['confidence']),
      maskCount: _safeInt(json['maskCount']),
      processingTimeMs: _safeDouble(json['processingTimeMs']),
      createdAt: DateTime.tryParse(_safeString(json['createdAt'])),
      comparisonGroupId: _nullableString(json['comparisonGroupId']),
      originalImageUrl: _nullableString(json['originalImageUrl']),
    );
  }

  final String id;
  final RecentActivityType type;
  final String fileName;
  final String modelType;
  final bool detected;
  final double confidence;
  final int maskCount;
  final double processingTimeMs;
  final DateTime? createdAt;
  final String? comparisonGroupId;
  final String? originalImageUrl;
}

class UserDashboard {
  const UserDashboard({
    required this.summary,
    required this.dailyUsage,
    required this.modelUsage,
    required this.predictionUsage,
    required this.recentActivities,
    required this.disclaimer,
  });

  factory UserDashboard.fromJson(Map<String, dynamic> json) {
    return UserDashboard(
      summary: DashboardSummary.fromJson(_safeMap(json['summary'])),
      dailyUsage: _safeList(json['dailyUsage'])
          .map((item) => DailyUsage.fromJson(_safeMap(item)))
          .toList(growable: false),
      modelUsage: ModelUsage.fromJson(_safeMap(json['modelUsage'])),
      predictionUsage: PredictionUsage.fromJson(
        _safeMap(json['predictionUsage']),
      ),
      recentActivities: _safeList(json['recentActivities'])
          .map((item) => RecentActivity.fromJson(_safeMap(item)))
          .toList(growable: false),
      disclaimer: _safeString(
        json['disclaimer'],
        fallback:
            'Các thống kê này phản ánh hoạt động sử dụng hệ thống và kết quả '
            'dự đoán đã lưu, không thay thế đánh giá thực nghiệm khoa học '
            'của mô hình.',
      ),
    );
  }

  final DashboardSummary summary;
  final List<DailyUsage> dailyUsage;
  final ModelUsage modelUsage;
  final PredictionUsage predictionUsage;
  final List<RecentActivity> recentActivities;
  final String disclaimer;

  bool get isEmpty =>
      summary.totalInferenceCount == 0 && recentActivities.isEmpty;
}

Map<String, dynamic> _safeMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

List<Object?> _safeList(Object? value) =>
    value is List ? List<Object?>.from(value) : const [];

int _safeInt(Object? value) =>
    value is num && value.isFinite ? value.toInt().clamp(0, 1 << 53) : 0;

double _safeDouble(Object? value) => value is num && value.isFinite
    ? value.toDouble().clamp(0, double.maxFinite)
    : 0;

double _ratio(Object? value) => _safeDouble(value).clamp(0, 1);

String _safeString(Object? value, {String fallback = ''}) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

String? _nullableString(Object? value) {
  final text = _safeString(value);
  return text.isEmpty ? null : text;
}
