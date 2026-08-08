import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';

enum DiagnosisStatus {
  idle,
  selecting,
  selected,
  uploading,
  processing,
  success,
  error,
  deleting,
}

class DiagnosisState {
  const DiagnosisState({
    this.status = DiagnosisStatus.idle,
    this.selectedImage,
    this.selectedModel = DiagnosisModelOption.baseline,
    this.uploadProgress = 0,
    this.result,
    this.message,
    this.requestId,
  });

  final DiagnosisStatus status;
  final SelectedDiagnosisImage? selectedImage;
  final DiagnosisModelOption selectedModel;
  final double uploadProgress;
  final DiagnosisResult? result;
  final String? message;
  final String? requestId;

  bool get isBusy =>
      status == DiagnosisStatus.selecting ||
      status == DiagnosisStatus.uploading ||
      status == DiagnosisStatus.processing ||
      status == DiagnosisStatus.deleting;

  bool get canAnalyze =>
      selectedImage != null &&
      selectedImage!.validationError == null &&
      !isBusy;

  DiagnosisState copyWith({
    DiagnosisStatus? status,
    SelectedDiagnosisImage? selectedImage,
    bool clearSelectedImage = false,
    DiagnosisModelOption? selectedModel,
    double? uploadProgress,
    DiagnosisResult? result,
    bool clearResult = false,
    String? message,
    bool clearMessage = false,
    String? requestId,
    bool clearRequestId = false,
  }) {
    return DiagnosisState(
      status: status ?? this.status,
      selectedImage: clearSelectedImage
          ? null
          : selectedImage ?? this.selectedImage,
      selectedModel: selectedModel ?? this.selectedModel,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      result: clearResult ? null : result ?? this.result,
      message: clearMessage ? null : message ?? this.message,
      requestId: clearRequestId ? null : requestId ?? this.requestId,
    );
  }
}
