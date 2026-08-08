import 'package:app_polyp/core/network/ai_api_exception.dart';
import 'package:app_polyp/core/network/ai_user_error_message.dart';
import 'package:app_polyp/features/ai/data/ai_repository.dart';
import 'package:app_polyp/features/ai/data/models/ai_models.dart';
import 'package:app_polyp/features/ai/presentation/providers/ai_providers.dart';
import 'package:app_polyp/features/comparison/direct_comparison_state.dart';
import 'package:app_polyp/shared/medical_image/medical_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final directComparisonImagePickerProvider = Provider<MedicalImagePicker>(
  (ref) => ref.watch(medicalImagePickerProvider),
);

final directComparisonControllerProvider =
    NotifierProvider<DirectComparisonController, DirectComparisonState>(
      DirectComparisonController.new,
    );

final class DirectComparisonController extends Notifier<DirectComparisonState> {
  late AiRepository _repository;
  late MedicalImagePicker _imagePicker;
  CancelToken? _activeRequest;
  bool _requestInProgress = false;
  bool _disposed = false;

  @override
  DirectComparisonState build() {
    _repository = ref.watch(directAiRepositoryProvider);
    _imagePicker = ref.watch(directComparisonImagePickerProvider);
    ref.onDispose(() {
      _disposed = true;
      _activeRequest?.cancel('Direct comparison provider disposed');
    });
    return const DirectComparisonState();
  }

  void synchronizeModelReadiness(bool bothModelsReady) {
    if (state.isBusy || state.image == null || state.hasResult) return;
    state = state.copyWith(
      status: bothModelsReady
          ? DirectComparisonStatus.ready
          : DirectComparisonStatus.imageSelected,
    );
  }

  Future<void> pickImage({required bool bothModelsReady}) async {
    if (state.isBusy) return;
    final previous = state;
    state = previous.copyWith(
      status: DirectComparisonStatus.selecting,
      clearMessage: true,
      clearRequestId: true,
    );
    try {
      final file = await _imagePicker.pickFromGallery();
      if (file == null) {
        state = previous;
        return;
      }
      final image = await MedicalImageValidator.validate(file);
      _cancelActiveRequest();
      state = DirectComparisonState(
        status: bothModelsReady
            ? DirectComparisonStatus.ready
            : DirectComparisonStatus.imageSelected,
        image: image,
      );
    } on MedicalImageValidationException catch (error) {
      state = previous.copyWith(
        status: DirectComparisonStatus.error,
        message: error.message,
        clearRequestId: true,
      );
    } catch (_) {
      state = previous.copyWith(
        status: DirectComparisonStatus.error,
        message: 'Không thể mở thư viện ảnh. Vui lòng thử lại.',
        clearRequestId: true,
      );
    }
  }

  void removeImage() {
    _cancelActiveRequest();
    state = const DirectComparisonState();
  }

  void reset() => removeImage();

  Future<AiComparisonResult?> compare({required bool bothModelsReady}) async {
    final image = state.image;
    if (_requestInProgress || state.isBusy || image == null) return null;
    if (!bothModelsReady) {
      state = state.copyWith(
        status: DirectComparisonStatus.error,
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
      status: DirectComparisonStatus.uploading,
      uploadProgress: 0,
      clearResult: true,
      clearMessage: true,
      clearRequestId: true,
    );

    try {
      final result = await _repository.compare(
        image: AiImageUpload(
          name: image.name,
          mimeType: image.mimeType,
          sizeBytes: image.sizeBytes,
          readBytes: () async => image.bytes,
        ),
        cancelToken: request,
        onSendProgress: (sent, total) {
          if (_disposed || _activeRequest != request || total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0);
          state = state.copyWith(
            status: progress >= 1
                ? DirectComparisonStatus.processing
                : DirectComparisonStatus.uploading,
            uploadProgress: progress,
          );
        },
      );
      if (_disposed || _activeRequest != request) return null;
      state = state.copyWith(
        status: DirectComparisonStatus.success,
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
            ? DirectComparisonStatus.cancelled
            : DirectComparisonStatus.error,
        message: aiUserErrorMessage(error),
        requestId: error.requestId,
        clearRequestId: error.requestId == null,
        clearResult: true,
      );
      return null;
    } catch (_) {
      if (_disposed || _activeRequest != request) return null;
      state = state.copyWith(
        status: DirectComparisonStatus.error,
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
      status: DirectComparisonStatus.cancelled,
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
