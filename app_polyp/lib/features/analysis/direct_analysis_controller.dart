import 'package:app_polyp/core/network/ai_api_exception.dart';
import 'package:app_polyp/core/network/ai_user_error_message.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/analysis/direct_analysis_state.dart';
import 'package:app_polyp/shared/medical_image/medical_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

const int maxDirectAnalysisImageBytes = maxMedicalImageBytes;

typedef DirectAnalysisImagePicker = MedicalImagePicker;

final directAnalysisImagePickerProvider = Provider<MedicalImagePicker>(
  (ref) => ref.watch(medicalImagePickerProvider),
);

final directAnalysisControllerProvider =
    NotifierProvider<DirectAnalysisController, DirectAnalysisState>(
      DirectAnalysisController.new,
    );

final class DirectAnalysisController extends Notifier<DirectAnalysisState> {
  late AiRepository _repository;
  late DirectAnalysisImagePicker _imagePicker;
  CancelToken? _activeRequest;
  bool _requestInProgress = false;
  bool _disposed = false;

  @override
  DirectAnalysisState build() {
    _repository = ref.watch(directAiRepositoryProvider);
    _imagePicker = ref.watch(directAnalysisImagePickerProvider);
    ref.onDispose(() {
      _disposed = true;
      _activeRequest?.cancel('Direct analysis provider disposed');
    });
    return const DirectAnalysisState();
  }

  void synchronizeModels(List<AiModelInfo> models) {
    if (state.selectedModelKey != null) return;
    final ready = models.where((model) => model.ready);
    if (ready.isEmpty) return;
    selectModel(
      ready.first.key,
      readyModelKeys: {for (final model in ready) model.key},
    );
  }

  void selectModel(String modelKey, {required Set<String> readyModelKeys}) {
    if (state.isBusy || !readyModelKeys.contains(modelKey)) return;
    state = state.copyWith(
      selectedModelKey: modelKey,
      status: state.image == null
          ? DirectAnalysisStatus.idle
          : DirectAnalysisStatus.ready,
      clearMessage: true,
    );
  }

  Future<void> pickImage() async {
    if (state.isBusy) return;
    final previous = state;
    state = previous.copyWith(
      status: DirectAnalysisStatus.selecting,
      clearMessage: true,
      clearRequestId: true,
    );
    try {
      final file = await _imagePicker.pickFromGallery();
      if (file == null) {
        state = previous;
        return;
      }
      final image = await DirectImageValidator.validate(file);
      _cancelActiveRequest();
      state = previous.copyWith(
        status: previous.selectedModelKey == null
            ? DirectAnalysisStatus.imageSelected
            : DirectAnalysisStatus.ready,
        image: image,
        uploadProgress: 0,
        clearResult: true,
        clearMessage: true,
        clearRequestId: true,
      );
    } on DirectImageValidationException catch (error) {
      state = previous.copyWith(
        status: DirectAnalysisStatus.error,
        message: error.message,
        clearRequestId: true,
      );
    } catch (_) {
      state = previous.copyWith(
        status: DirectAnalysisStatus.error,
        message: 'Không thể mở thư viện ảnh. Vui lòng thử lại.',
        clearRequestId: true,
      );
    }
  }

  void removeImage() {
    _cancelActiveRequest();
    state = DirectAnalysisState(selectedModelKey: state.selectedModelKey);
  }

  void reset() => removeImage();

  Future<AiInferenceResult?> analyze({
    required Set<String> readyModelKeys,
  }) async {
    final image = state.image;
    final modelKey = state.selectedModelKey;
    if (_requestInProgress ||
        state.isBusy ||
        image == null ||
        modelKey == null) {
      return null;
    }
    if (!readyModelKeys.contains(modelKey)) {
      state = state.copyWith(
        status: DirectAnalysisStatus.error,
        message: 'Mô hình hiện chưa sẵn sàng.',
        clearResult: true,
      );
      return null;
    }

    _cancelActiveRequest();
    final request = CancelToken();
    _activeRequest = request;
    _requestInProgress = true;
    state = state.copyWith(
      status: DirectAnalysisStatus.uploading,
      uploadProgress: 0,
      clearResult: true,
      clearMessage: true,
      clearRequestId: true,
    );

    try {
      final result = await _repository.infer(
        image: AiImageUpload(
          name: image.name,
          mimeType: image.mimeType,
          sizeBytes: image.sizeBytes,
          readBytes: () async => image.bytes,
        ),
        modelKey: modelKey,
        cancelToken: request,
        onSendProgress: (sent, total) {
          if (_disposed || _activeRequest != request || total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0);
          state = state.copyWith(
            status: progress >= 1
                ? DirectAnalysisStatus.processing
                : DirectAnalysisStatus.uploading,
            uploadProgress: progress,
          );
        },
      );
      if (_disposed || _activeRequest != request) return null;
      state = state.copyWith(
        status: DirectAnalysisStatus.success,
        uploadProgress: 1,
        result: result,
        requestId: result.requestId,
        clearMessage: true,
      );
      return result;
    } on AiApiException catch (error) {
      if (_disposed || _activeRequest != request) return null;
      state = state.copyWith(
        status: error.kind == AiFailureKind.cancelled
            ? DirectAnalysisStatus.cancelled
            : DirectAnalysisStatus.error,
        message: directAnalysisErrorMessage(error),
        requestId: error.requestId,
        clearRequestId: error.requestId == null,
        clearResult: true,
      );
      return null;
    } catch (_) {
      if (_disposed || _activeRequest != request) return null;
      state = state.copyWith(
        status: DirectAnalysisStatus.error,
        message: 'Không thể hoàn tất quá trình phân tích.',
        clearResult: true,
        clearRequestId: true,
      );
      return null;
    } finally {
      if (_activeRequest == request) {
        _activeRequest = null;
        _requestInProgress = false;
      }
    }
  }

  void cancel() {
    if (!_requestInProgress) return;
    final request = _activeRequest;
    _activeRequest = null;
    _requestInProgress = false;
    request?.cancel('Cancelled by user');
    state = state.copyWith(
      status: DirectAnalysisStatus.cancelled,
      uploadProgress: 0,
      message: 'Yêu cầu đã được hủy.',
      clearResult: true,
      clearRequestId: true,
    );
  }

  void _cancelActiveRequest() {
    _activeRequest?.cancel('Superseded by a new operation');
    _activeRequest = null;
    _requestInProgress = false;
  }
}

String directAnalysisErrorMessage(AiApiException error) =>
    aiUserErrorMessage(error);

abstract final class DirectImageValidator {
  static Future<SelectedMedicalImage> validate(XFile file) =>
      MedicalImageValidator.validate(file);
}

typedef DirectImageValidationException = MedicalImageValidationException;
