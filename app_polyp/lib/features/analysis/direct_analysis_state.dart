import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/shared/medical_image/medical_image.dart';

enum DirectAnalysisStatus {
  idle,
  selecting,
  imageSelected,
  ready,
  uploading,
  processing,
  success,
  error,
  cancelled,
}

typedef DirectSelectedImage = SelectedMedicalImage;

final class DirectAnalysisState {
  const DirectAnalysisState({
    this.status = DirectAnalysisStatus.idle,
    this.image,
    this.selectedModelKey,
    this.uploadProgress = 0,
    this.result,
    this.message,
    this.requestId,
  });

  final DirectAnalysisStatus status;
  final DirectSelectedImage? image;
  final String? selectedModelKey;
  final double uploadProgress;
  final AiInferenceResult? result;
  final String? message;
  final String? requestId;

  bool get isBusy =>
      status == DirectAnalysisStatus.selecting ||
      status == DirectAnalysisStatus.uploading ||
      status == DirectAnalysisStatus.processing;

  bool get hasResult =>
      status == DirectAnalysisStatus.success && result != null;

  DirectAnalysisState copyWith({
    DirectAnalysisStatus? status,
    DirectSelectedImage? image,
    bool clearImage = false,
    String? selectedModelKey,
    bool clearSelectedModel = false,
    double? uploadProgress,
    AiInferenceResult? result,
    bool clearResult = false,
    String? message,
    bool clearMessage = false,
    String? requestId,
    bool clearRequestId = false,
  }) => DirectAnalysisState(
    status: status ?? this.status,
    image: clearImage ? null : image ?? this.image,
    selectedModelKey: clearSelectedModel
        ? null
        : selectedModelKey ?? this.selectedModelKey,
    uploadProgress: uploadProgress ?? this.uploadProgress,
    result: clearResult ? null : result ?? this.result,
    message: clearMessage ? null : message ?? this.message,
    requestId: clearRequestId ? null : requestId ?? this.requestId,
  );
}
