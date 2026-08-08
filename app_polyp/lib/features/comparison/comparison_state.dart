import 'package:app_polyp/features/comparison/comparison_models.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';

enum ComparisonStatus {
  idle,
  selecting,
  selected,
  uploading,
  processing,
  success,
  error,
  deleting,
}

class ComparisonState {
  const ComparisonState({
    this.status = ComparisonStatus.idle,
    this.selectedImage,
    this.uploadProgress = 0,
    this.result,
    this.message,
    this.requestId,
  });

  final ComparisonStatus status;
  final SelectedDiagnosisImage? selectedImage;
  final double uploadProgress;
  final ComparisonResult? result;
  final String? message;
  final String? requestId;

  bool get isBusy =>
      status == ComparisonStatus.selecting ||
      status == ComparisonStatus.uploading ||
      status == ComparisonStatus.processing ||
      status == ComparisonStatus.deleting;

  bool get canCompare =>
      selectedImage != null &&
      selectedImage!.validationError == null &&
      !isBusy;

  ComparisonState copyWith({
    ComparisonStatus? status,
    SelectedDiagnosisImage? selectedImage,
    bool clearSelectedImage = false,
    double? uploadProgress,
    ComparisonResult? result,
    bool clearResult = false,
    String? message,
    bool clearMessage = false,
    String? requestId,
    bool clearRequestId = false,
  }) => ComparisonState(
    status: status ?? this.status,
    selectedImage: clearSelectedImage
        ? null
        : selectedImage ?? this.selectedImage,
    uploadProgress: uploadProgress ?? this.uploadProgress,
    result: clearResult ? null : result ?? this.result,
    message: clearMessage ? null : message ?? this.message,
    requestId: clearRequestId ? null : requestId ?? this.requestId,
  );
}
