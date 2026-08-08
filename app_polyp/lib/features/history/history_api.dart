import 'package:app_polyp/core/network/api_client.dart';
import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_controller.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/history/history_filters.dart';
import 'package:app_polyp/features/history/history_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class HistoryRepository {
  Future<PagedResponse<DiagnosisHistoryItem>> getDiagnoses(
    DiagnosisHistoryFilter filter,
    int page,
  );

  Future<PagedResponse<ComparisonHistoryItem>> getComparisons(
    ComparisonHistoryFilter filter,
    int page,
  );

  Future<void> deleteDiagnosis(String id);
  Future<void> deleteComparison(String comparisonGroupId);
}

class HistoryApi implements HistoryRepository {
  const HistoryApi(this._client, this._csrf);

  final ApiClient _client;
  final CsrfController _csrf;

  @override
  Future<PagedResponse<DiagnosisHistoryItem>> getDiagnoses(
    DiagnosisHistoryFilter filter,
    int page,
  ) async {
    final json = await _client.getJson(
      _url('/api/v1/diagnoses', filter.query(page)),
    );
    return _parsePage(json, DiagnosisHistoryItem.fromJson);
  }

  @override
  Future<PagedResponse<ComparisonHistoryItem>> getComparisons(
    ComparisonHistoryFilter filter,
    int page,
  ) async {
    final json = await _client.getJson(
      _url('/api/v1/comparisons', filter.query(page)),
    );
    return _parsePage(json, ComparisonHistoryItem.fromJson);
  }

  @override
  Future<void> deleteDiagnosis(String id) async {
    await _csrf.ensure();
    await _client.deleteNoContent('/api/v1/diagnoses/$id');
  }

  @override
  Future<void> deleteComparison(String comparisonGroupId) async {
    await _csrf.ensure();
    await _client.deleteNoContent('/api/v1/comparisons/$comparisonGroupId');
  }

  PagedResponse<T> _parsePage<T>(
    Map<String, dynamic> json,
    JsonItemParser<T> parser,
  ) {
    try {
      return PagedResponse.fromJson(json, parser);
    } catch (_) {
      throw const ApiException(
        code: 'INVALID_RESPONSE',
        message: 'Máy chủ trả về dữ liệu lịch sử không hợp lệ.',
      );
    }
  }

  String _url(String path, Map<String, dynamic> query) => Uri(
    path: path,
    queryParameters: query.map((key, value) => MapEntry(key, '$value')),
  ).toString();
}

final historyApiProvider = Provider<HistoryRepository>(
  (ref) => HistoryApi(
    ref.watch(apiClientProvider),
    ref.watch(csrfControllerProvider),
  ),
);
