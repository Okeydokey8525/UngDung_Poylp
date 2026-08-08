import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/features/account/account_api.dart';
import 'package:app_polyp/features/account/account_models.dart';
import 'package:app_polyp/features/account/account_state.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final accountControllerProvider =
    NotifierProvider<AccountController, AccountOperationState>(
      AccountController.new,
    );

class AccountController extends Notifier<AccountOperationState> {
  bool _requestInProgress = false;
  late AccountRepository _repository;

  @override
  AccountOperationState build() {
    _repository = ref.watch(accountApiProvider);
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.authenticated) {
        state = const AccountOperationState();
      }
    });
    return const AccountOperationState();
  }

  Future<ProfileUpdateOutcome?> updateProfile(
    ProfileUpdateRequest request,
  ) async {
    if (_requestInProgress) return null;
    _requestInProgress = true;
    state = const AccountOperationState(
      status: AccountOperationStatus.submitting,
    );
    try {
      final result = await _repository.updateProfile(request);
      if (result.reauthenticationRequired) {
        state = const AccountOperationState(
          status: AccountOperationStatus.success,
          message: 'Hồ sơ đã cập nhật. Vui lòng đăng nhập lại.',
        );
        await ref
            .read(authControllerProvider.notifier)
            .clearSessionAfterSensitiveChange(
              message:
                  'Email đã được cập nhật. Vui lòng đăng nhập lại bằng email mới.',
              emailHint: result.user.email,
            );
        return ProfileUpdateOutcome.reauthenticationRequired;
      }
      ref.read(authControllerProvider.notifier).updateCurrentUser(result.user);
      state = const AccountOperationState(
        status: AccountOperationStatus.success,
        message: 'Cập nhật hồ sơ thành công.',
      );
      return ProfileUpdateOutcome.updated;
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await ref
            .read(authControllerProvider.notifier)
            .clearSessionAfterSensitiveChange(
              message: 'Phiên đăng nhập đã hết hạn.',
            );
      } else {
        state = AccountOperationState(
          status: AccountOperationStatus.failure,
          message: error.message,
          fieldErrors: error.fieldErrors,
          requestId: error.requestId,
        );
      }
      return null;
    } catch (_) {
      state = const AccountOperationState(
        status: AccountOperationStatus.failure,
        message: 'Đã xảy ra lỗi, vui lòng thử lại.',
      );
      return null;
    } finally {
      _requestInProgress = false;
    }
  }

  Future<bool> changePassword(PasswordChangeRequest request) async {
    if (_requestInProgress) return false;
    _requestInProgress = true;
    state = const AccountOperationState(
      status: AccountOperationStatus.submitting,
    );
    try {
      await _repository.changePassword(request);
      state = const AccountOperationState(
        status: AccountOperationStatus.success,
        message: 'Đổi mật khẩu thành công.',
      );
      await ref
          .read(authControllerProvider.notifier)
          .clearSessionAfterSensitiveChange(
            message: 'Đổi mật khẩu thành công. Vui lòng đăng nhập lại.',
          );
      return true;
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await ref
            .read(authControllerProvider.notifier)
            .clearSessionAfterSensitiveChange(
              message: 'Phiên đăng nhập đã hết hạn.',
            );
      } else {
        state = AccountOperationState(
          status: AccountOperationStatus.failure,
          message: error.message,
          fieldErrors: error.fieldErrors,
          requestId: error.requestId,
        );
      }
      return false;
    } catch (_) {
      state = const AccountOperationState(
        status: AccountOperationStatus.failure,
        message: 'Đã xảy ra lỗi, vui lòng thử lại.',
      );
      return false;
    } finally {
      _requestInProgress = false;
    }
  }

  void clearFeedback() {
    if (!_requestInProgress) {
      state = const AccountOperationState();
    }
  }
}
