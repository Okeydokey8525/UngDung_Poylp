import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_api.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_state.dart';
import 'package:app_polyp/features/history/history_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

abstract interface class DiagnosisImagePicker {
  Future<SelectedDiagnosisImage?> pickFromGallery();
}

class GalleryDiagnosisImagePicker implements DiagnosisImagePicker {
  GalleryDiagnosisImagePicker(this._picker);

  final ImagePicker _picker;

  @override
  Future<SelectedDiagnosisImage?> pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final name = file.name;
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
    return SelectedDiagnosisImage(
      file: file,
      name: name,
      mimeType: mimeType,
      sizeBytes: await file.length(),
    );
  }
}

final diagnosisImagePickerProvider = Provider<DiagnosisImagePicker>(
  (ref) => GalleryDiagnosisImagePicker(ImagePicker()),
);

final diagnosisControllerProvider =
    NotifierProvider<DiagnosisController, DiagnosisState>(
      DiagnosisController.new,
    );

class DiagnosisController extends Notifier<DiagnosisState> {
  bool _operationInProgress = false;
  late DiagnosisRepository _repository;
  late DiagnosisImagePicker _imagePicker;

  @override
  DiagnosisState build() {
    _repository = ref.watch(diagnosisApiProvider);
    _imagePicker = ref.watch(diagnosisImagePickerProvider);
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.authenticated) {
        state = const DiagnosisState();
      }
    });
    return const DiagnosisState();
  }

  Future<void> pickImage() async {
    if (_operationInProgress) return;
    _operationInProgress = true;
    final previous = state;
    state = previous.copyWith(
      status: DiagnosisStatus.selecting,
      clearMessage: true,
      clearRequestId: true,
    );
    try {
      final selected = await _imagePicker.pickFromGallery();
      if (selected == null) {
        state = previous;
        return;
      }
      state = previous.copyWith(
        status: DiagnosisStatus.selected,
        selectedImage: selected,
        clearResult: true,
        message: selected.validationError,
        clearMessage: selected.validationError == null,
      );
    } catch (_) {
      state = previous.copyWith(
        status: DiagnosisStatus.error,
        message: 'Không thể mở thư viện ảnh. Vui lòng thử lại.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  void selectModel(DiagnosisModelOption model) {
    if (_operationInProgress) return;
    state = state.copyWith(selectedModel: model, clearMessage: true);
  }

  Future<DiagnosisResult?> analyze() async {
    final image = state.selectedImage;
    if (_operationInProgress ||
        image == null ||
        image.validationError != null) {
      return null;
    }
    _operationInProgress = true;
    state = state.copyWith(
      status: DiagnosisStatus.uploading,
      uploadProgress: 0,
      clearMessage: true,
      clearRequestId: true,
      clearResult: true,
    );
    try {
      final result = await _repository.createDiagnosis(
        image,
        state.selectedModel,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0);
          state = state.copyWith(
            status: progress >= 1
                ? DiagnosisStatus.processing
                : DiagnosisStatus.uploading,
            uploadProgress: progress,
          );
        },
      );
      state = state.copyWith(
        status: DiagnosisStatus.success,
        uploadProgress: 1,
        result: result,
        clearMessage: true,
      );
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(diagnosisHistoryControllerProvider);
      return result;
    } on ApiException catch (error) {
      await _handleApiError(error, keepResult: false);
      return null;
    } catch (_) {
      state = state.copyWith(
        status: DiagnosisStatus.error,
        message: 'Đã xảy ra lỗi khi phân tích ảnh. Vui lòng thử lại.',
      );
      return null;
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> openResult(String id, {DiagnosisResult? initialResult}) async {
    if (initialResult != null && initialResult.id == id) {
      state = state.copyWith(
        status: DiagnosisStatus.success,
        result: initialResult,
        clearMessage: true,
      );
      return;
    }
    if (state.result?.id == id && state.status == DiagnosisStatus.success) {
      return;
    }
    if (_operationInProgress) return;
    _operationInProgress = true;
    state = state.copyWith(
      status: DiagnosisStatus.processing,
      clearResult: true,
      clearMessage: true,
      clearRequestId: true,
    );
    try {
      final result = await _repository.getDiagnosis(id);
      state = state.copyWith(status: DiagnosisStatus.success, result: result);
    } on ApiException catch (error) {
      await _handleApiError(error, keepResult: false);
    } catch (_) {
      state = state.copyWith(
        status: DiagnosisStatus.error,
        message: 'Không thể tải kết quả phân tích.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<bool> deleteCurrent() async {
    final result = state.result;
    if (_operationInProgress || result == null) return false;
    _operationInProgress = true;
    state = state.copyWith(
      status: DiagnosisStatus.deleting,
      clearMessage: true,
      clearRequestId: true,
    );
    try {
      await _repository.deleteDiagnosis(result.id);
      state = const DiagnosisState();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(diagnosisHistoryControllerProvider);
      return true;
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await _expireSession();
      } else {
        state = state.copyWith(
          status: DiagnosisStatus.success,
          result: result,
          message: error.message,
          requestId: error.requestId,
        );
      }
      return false;
    } catch (_) {
      state = state.copyWith(
        status: DiagnosisStatus.success,
        result: result,
        message: 'Không thể xóa kết quả. Vui lòng thử lại.',
      );
      return false;
    } finally {
      _operationInProgress = false;
    }
  }

  void analyzeAnother() {
    if (_operationInProgress) return;
    state = DiagnosisState(selectedModel: state.selectedModel);
  }

  Future<void> _handleApiError(
    ApiException error, {
    required bool keepResult,
  }) async {
    if (error.isUnauthenticated) {
      await _expireSession();
      return;
    }
    state = state.copyWith(
      status: DiagnosisStatus.error,
      clearResult: !keepResult,
      message: error.message,
      requestId: error.requestId,
    );
  }

  Future<void> _expireSession() => ref
      .read(authControllerProvider.notifier)
      .clearSessionAfterSensitiveChange(message: 'Phiên đăng nhập đã hết hạn.');
}
