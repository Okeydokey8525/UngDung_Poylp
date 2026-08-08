import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/dashboard/dashboard_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class DashboardRepository {
  Future<UserDashboard> fetchDashboard();
}

class DashboardApi implements DashboardRepository {
  const DashboardApi(this._client);

  final ApiClient _client;

  @override
  Future<UserDashboard> fetchDashboard() async {
    final json = await _client.getJson('/api/v1/dashboard');
    try {
      return UserDashboard.fromJson(json);
    } on FormatException {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về phản hồi không hợp lệ.',
      );
    }
  }
}

final dashboardApiProvider = Provider<DashboardRepository>(
  (ref) => DashboardApi(ref.watch(apiClientProvider)),
);
