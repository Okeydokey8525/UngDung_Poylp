import 'package:app_polyp/features/dashboard/dashboard_models.dart';

enum DashboardStatus { initial, loading, data, empty, error, refreshing }

class DashboardState {
  const DashboardState({
    this.status = DashboardStatus.initial,
    this.dashboard,
    this.message,
    this.requestId,
    this.refreshMessage,
  });

  final DashboardStatus status;
  final UserDashboard? dashboard;
  final String? message;
  final String? requestId;
  final String? refreshMessage;
}
