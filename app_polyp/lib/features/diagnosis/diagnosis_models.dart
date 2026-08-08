import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

const maxDiagnosisUploadBytes = 10 * 1024 * 1024;

enum DiagnosisModelOption {
  baseline(
    apiValue: 'YOLO26n-seg',
    category: 'Baseline',
    description: 'Phiên bản nano ưu tiên tốc độ và tài nguyên tính toán thấp.',
  ),
  vmamba(
    apiValue: 'YOLO26n-VMamba-seg',
    category: 'VMamba',
    description: 'Biến thể nano tích hợp VMambaBlock ở feature map mức cao.',
  );

  const DiagnosisModelOption({
    required this.apiValue,
    required this.category,
    required this.description,
  });

  final String apiValue;
  final String category;
  final String description;
}

class SelectedDiagnosisImage {
  const SelectedDiagnosisImage({
    required this.file,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
  });

  final XFile file;
  final String name;
  final String mimeType;
  final int sizeBytes;

  String? get validationError {
    if (sizeBytes <= 0) return 'Tệp ảnh đang rỗng.';
    if (sizeBytes > maxDiagnosisUploadBytes) {
      return 'Dung lượng ảnh vượt quá 10 MB.';
    }
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    if (!const {'jpg', 'jpeg', 'png'}.contains(extension)) {
      return 'Chỉ hỗ trợ phần mở rộng JPG, JPEG hoặc PNG.';
    }
    if (!const {'image/jpeg', 'image/png'}.contains(mimeType)) {
      return 'Định dạng ảnh không được hỗ trợ.';
    }
    if (mimeType == 'image/png' && extension != 'png') {
      return 'MIME và phần mở rộng ảnh không khớp.';
    }
    if (mimeType == 'image/jpeg' && extension != 'jpg' && extension != 'jpeg') {
      return 'MIME và phần mở rộng ảnh không khớp.';
    }
    return null;
  }

  Future<Uint8List> readBytes() => file.readAsBytes();
}

class DiagnosisResult {
  const DiagnosisResult({
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
    required this.metadataUrl,
  });

  factory DiagnosisResult.fromJson(Map<String, dynamic> json) {
    return DiagnosisResult(
      id: _safeString(json['id']),
      fileName: _safeString(json['fileName'], fallback: 'Ảnh nội soi'),
      modelType: _safeString(json['modelType'], fallback: 'Không xác định'),
      modelCategory: _safeString(json['modelCategory'], fallback: 'UNKNOWN'),
      detected: json['detected'] == true,
      label: _nullableString(json['label']),
      confidence: _ratio(json['confidence']),
      maskCount: _safeInt(json['maskCount']),
      processingTimeMs: _safeDouble(json['processingTimeMs']),
      createdAt: DateTime.tryParse(_safeString(json['createdAt'])),
      originalImageUrl: _safeString(json['originalImageUrl']),
      resultImageUrl: _safeString(json['resultImageUrl']),
      metadataUrl: _safeString(json['metadataUrl']),
    );
  }

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
  final String metadataUrl;
}

String _safeString(Object? value, {String fallback = ''}) =>
    value is String && value.trim().isNotEmpty ? value.trim() : fallback;

String? _nullableString(Object? value) {
  final text = _safeString(value);
  return text.isEmpty ? null : text;
}

int _safeInt(Object? value) =>
    value is num && value.isFinite ? value.toInt().clamp(0, 1 << 53) : 0;

double _safeDouble(Object? value) => value is num && value.isFinite
    ? value.toDouble().clamp(0, double.maxFinite)
    : 0;

double _ratio(Object? value) => _safeDouble(value).clamp(0, 1);
