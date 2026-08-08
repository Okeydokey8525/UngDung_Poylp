import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:app_polyp/features/dashboard/dashboard_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final dashboardControllerProvider =
    NotifierProvider<DashboardController, DashboardState>(
      DashboardController.new,
    );

class DashboardController extends Notifier<DashboardState> {
  bool _requestInProgress = false;
  late DashboardRepository _repository;

  @override
  DashboardState build() {
    _repository = ref.watch(dashboardApiProvider);
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.authenticated) {
        state = const DashboardState();
      }
    });
    return const DashboardState();
  }

  Future<void> load({bool force = false}) async {
    if (_requestInProgress) return;
    if (!force &&
        (state.status == DashboardStatus.data ||
            state.status == DashboardStatus.empty)) {
      return;
    }
    await _request(refresh: false);
  }

  Future<void> refresh() => _request(refresh: true);

  Future<void> _request({required bool refresh}) async {
    if (_requestInProgress) return;
    _requestInProgress = true;
    final previous = state.dashboard;
    state = DashboardState(
      status: refresh && previous != null
          ? DashboardStatus.refreshing
          : DashboardStatus.loading,
      dashboard: previous,
    );
    try {
      final dashboard = await _repository.fetchDashboard();
      state = DashboardState(
        status: dashboard.isEmpty
            ? DashboardStatus.empty
            : DashboardStatus.data,
        dashboard: dashboard,
      );
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await ref
            .read(authControllerProvider.notifier)
            .clearSessionAfterSensitiveChange(
              message: 'Phiên đăng nhập đã hết hạn.',
            );
        state = const DashboardState();
      } else if (refresh && previous != null) {
        state = DashboardState(
          status: previous.isEmpty
              ? DashboardStatus.empty
              : DashboardStatus.data,
          dashboard: previous,
          refreshMessage: error.message,
        );
      } else {
        state = DashboardState(
          status: DashboardStatus.error,
          message: error.message,
          requestId: error.requestId,
        );
      }
    } catch (_) {
      state = const DashboardState(
        status: DashboardStatus.error,
        message: 'Đã xảy ra lỗi, vui lòng thử lại.',
      );
    } finally {
      _requestInProgress = false;
    }
  }
}
