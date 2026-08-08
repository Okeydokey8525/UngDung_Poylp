import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/comparison/comparison_api.dart';
import 'package:app_polyp/features/comparison/comparison_models.dart';
import 'package:app_polyp/features/comparison/comparison_state.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_controller.dart';
import 'package:app_polyp/features/history/history_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final comparisonControllerProvider =
    NotifierProvider<ComparisonController, ComparisonState>(
      ComparisonController.new,
    );

class ComparisonController extends Notifier<ComparisonState> {
  bool _operationInProgress = false;
  late ComparisonRepository _repository;
  late DiagnosisImagePicker _imagePicker;

  @override
  ComparisonState build() {
    _repository = ref.watch(comparisonApiProvider);
    _imagePicker = ref.watch(diagnosisImagePickerProvider);
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.authenticated) {
        state = const ComparisonState();
      }
    });
    return const ComparisonState();
  }

  Future<void> pickImage() async {
    if (_operationInProgress) return;
    _operationInProgress = true;
    final previous = state;
    state = previous.copyWith(
      status: ComparisonStatus.selecting,
      clearMessage: true,
      clearRequestId: true,
    );
    try {
      final selected = await _imagePicker.pickFromGallery();
      if (selected == null) {
        state = previous;
      } else {
        state = previous.copyWith(
          status: ComparisonStatus.selected,
          selectedImage: selected,
          clearResult: true,
          message: selected.validationError,
          clearMessage: selected.validationError == null,
        );
      }
    } catch (_) {
      state = previous.copyWith(
        status: ComparisonStatus.error,
        message: 'Không thể mở thư viện ảnh. Vui lòng thử lại.',
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<ComparisonResult?> compare() async {
    final image = state.selectedImage;
    if (_operationInProgress ||
        image == null ||
        image.validationError != null) {
      return null;
    }
    _operationInProgress = true;
    state = state.copyWith(
      status: ComparisonStatus.uploading,
      uploadProgress: 0,
      clearResult: true,
      clearMessage: true,
      clearRequestId: true,
    );
    try {
      final result = await _repository.createComparison(
        image,
        onSendProgress: (sent, total) {
          if (total <= 0) return;
          final progress = (sent / total).clamp(0.0, 1.0);
          state = state.copyWith(
            status: progress >= 1
                ? ComparisonStatus.processing
                : ComparisonStatus.uploading,
            uploadProgress: progress,
          );
        },
      );
      state = state.copyWith(
        status: ComparisonStatus.success,
        uploadProgress: 1,
        result: result,
      );
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(comparisonHistoryControllerProvider);
      return result;
    } on ApiException catch (error) {
      await _handleApiError(error);
      return null;
    } catch (_) {
      state = state.copyWith(
        status: ComparisonStatus.error,
        message: 'Không thể hoàn tất phiên so sánh. Vui lòng thử lại.',
      );
      return null;
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> openResult(
    String comparisonGroupId, {
    ComparisonResult? initialResult,
  }) async {
    if (initialResult?.comparisonGroupId == comparisonGroupId) {
      state = state.copyWith(
        status: ComparisonStatus.success,
        result: initialResult,
        clearMessage: true,
      );
      return;
    }
    if (state.result?.comparisonGroupId == comparisonGroupId &&
        state.status == ComparisonStatus.success) {
      return;
    }
    if (_operationInProgress) return;
    _operationInProgress = true;
    state = state.copyWith(
      status: ComparisonStatus.processing,
      clearResult: true,
      clearMessage: true,
    );
    try {
      final result = await _repository.getComparison(comparisonGroupId);
      state = state.copyWith(status: ComparisonStatus.success, result: result);
    } on ApiException catch (error) {
      await _handleApiError(error);
    } catch (_) {
      state = state.copyWith(
        status: ComparisonStatus.error,
        message: 'Không thể tải phiên so sánh.',
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
      status: ComparisonStatus.deleting,
      clearMessage: true,
    );
    try {
      await _repository.deleteComparison(result.comparisonGroupId);
      state = const ComparisonState();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(comparisonHistoryControllerProvider);
      return true;
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await _expireSession();
      } else {
        state = state.copyWith(
          status: ComparisonStatus.success,
          result: result,
          message: error.message,
          requestId: error.requestId,
        );
      }
      return false;
    } catch (_) {
      state = state.copyWith(
        status: ComparisonStatus.success,
        result: result,
        message: 'Không thể xóa phiên so sánh.',
      );
      return false;
    } finally {
      _operationInProgress = false;
    }
  }

  void compareAnother() {
    if (!_operationInProgress) state = const ComparisonState();
  }

  Future<void> _handleApiError(ApiException error) async {
    if (error.isUnauthenticated) {
      await _expireSession();
    } else {
      state = state.copyWith(
        status: ComparisonStatus.error,
        clearResult: true,
        message: error.message,
        requestId: error.requestId,
      );
    }
  }

  Future<void> _expireSession() => ref
      .read(authControllerProvider.notifier)
      .clearSessionAfterSensitiveChange(message: 'Phiên đăng nhập đã hết hạn.');
}
