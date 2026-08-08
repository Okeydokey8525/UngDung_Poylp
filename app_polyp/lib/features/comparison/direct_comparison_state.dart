import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/shared/medical_image/medical_image.dart';

enum DirectComparisonStatus {
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

final class DirectComparisonState {
  const DirectComparisonState({
    this.status = DirectComparisonStatus.idle,
    this.image,
    this.uploadProgress = 0,
    this.result,
    this.message,
    this.requestId,
  });

  final DirectComparisonStatus status;
  final SelectedMedicalImage? image;
  final double uploadProgress;
  final AiComparisonResult? result;
  final String? message;
  final String? requestId;

  bool get isBusy =>
      status == DirectComparisonStatus.selecting ||
      status == DirectComparisonStatus.uploading ||
      status == DirectComparisonStatus.processing;

  bool get hasResult =>
      status == DirectComparisonStatus.success && result != null;

  DirectComparisonState copyWith({
    DirectComparisonStatus? status,
    SelectedMedicalImage? image,
    bool clearImage = false,
    double? uploadProgress,
    AiComparisonResult? result,
    bool clearResult = false,
    String? message,
    bool clearMessage = false,
    String? requestId,
    bool clearRequestId = false,
  }) => DirectComparisonState(
    status: status ?? this.status,
    image: clearImage ? null : image ?? this.image,
    uploadProgress: uploadProgress ?? this.uploadProgress,
    result: clearResult ? null : result ?? this.result,
    message: clearMessage ? null : message ?? this.message,
    requestId: clearRequestId ? null : requestId ?? this.requestId,
  );
}
