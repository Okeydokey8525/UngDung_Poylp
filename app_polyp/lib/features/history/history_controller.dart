import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/features/auth/auth_controller.dart';
import 'package:app_polyp/features/auth/auth_state.dart';
import 'package:app_polyp/features/dashboard/dashboard_controller.dart';
import 'package:app_polyp/features/history/history_api.dart';
import 'package:app_polyp/features/history/history_filters.dart';
import 'package:app_polyp/features/history/history_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final diagnosisHistoryControllerProvider =
    NotifierProvider<DiagnosisHistoryController, DiagnosisHistoryState>(
      DiagnosisHistoryController.new,
    );

final comparisonHistoryControllerProvider =
    NotifierProvider<ComparisonHistoryController, ComparisonHistoryState>(
      ComparisonHistoryController.new,
    );

class DiagnosisHistoryController extends Notifier<DiagnosisHistoryState> {
  late HistoryRepository _repository;
  bool _busy = false;
  int _requestId = 0;

  @override
  DiagnosisHistoryState build() {
    _repository = ref.watch(historyApiProvider);
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.authenticated) {
        _requestId++;
        state = const DiagnosisHistoryState();
      }
    });
    return const DiagnosisHistoryState();
  }

  Future<void> load({bool force = false}) async {
    if (_busy || (!force && state.status != HistoryStatus.idle)) return;
    await _fetch(0, replace: true, refreshing: false);
  }

  Future<void> refresh() => _fetch(0, replace: true, refreshing: true);

  Future<void> applyFilter(DiagnosisHistoryFilter filter) async {
    if (filter.dateError != null) return;
    state = DiagnosisHistoryState(filter: filter);
    await _fetch(0, replace: true, refreshing: false);
  }

  Future<void> search(String keyword) =>
      applyFilter(state.filter.copyWith(keyword: keyword));

  Future<void> clearSearch() => applyFilter(state.filter.copyWith(keyword: ''));

  Future<void> resetFilter() => applyFilter(const DiagnosisHistoryFilter());

  Future<void> loadMore() async {
    if (_busy || !state.hasNext) return;
    await _fetch(state.currentPage + 1, replace: false, refreshing: false);
  }

  Future<bool> deleteItem(String id) async {
    if (_busy || !state.items.any((item) => item.id == id)) return false;
    _busy = true;
    final previous = state;
    state = DiagnosisHistoryState(
      status: HistoryStatus.deleting,
      items: previous.items,
      currentPage: previous.currentPage,
      totalPages: previous.totalPages,
      totalItems: previous.totalItems,
      hasNext: previous.hasNext,
      filter: previous.filter,
    );
    try {
      await _repository.deleteDiagnosis(id);
      final remaining = previous.items.where((item) => item.id != id).toList();
      state = DiagnosisHistoryState(
        status: remaining.isEmpty ? HistoryStatus.empty : HistoryStatus.data,
        items: remaining,
        currentPage: previous.currentPage,
        totalPages: previous.totalPages,
        totalItems: (previous.totalItems - 1).clamp(0, 1 << 31),
        hasNext: previous.hasNext,
        filter: previous.filter,
      );
      ref.invalidate(dashboardControllerProvider);
      _busy = false;
      if (remaining.isEmpty && previous.currentPage > 0) {
        await _fetch(
          previous.currentPage - 1,
          replace: true,
          refreshing: false,
        );
      }
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        _busy = false;
        await _fetch(0, replace: true, refreshing: false);
      } else {
        await _deleteError(error, previous);
      }
      return false;
    } catch (_) {
      state = _diagnosisWithMessage(previous, 'Không thể xóa kết quả.');
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<void> _fetch(
    int page, {
    required bool replace,
    required bool refreshing,
  }) async {
    if (_busy) return;
    _busy = true;
    final token = ++_requestId;
    final previous = state;
    state = DiagnosisHistoryState(
      status: refreshing && previous.items.isNotEmpty
          ? HistoryStatus.refreshing
          : replace
          ? HistoryStatus.loading
          : HistoryStatus.loadingNextPage,
      items: previous.items,
      currentPage: previous.currentPage,
      totalPages: previous.totalPages,
      totalItems: previous.totalItems,
      hasNext: previous.hasNext,
      filter: previous.filter,
    );
    try {
      final response = await _repository.getDiagnoses(previous.filter, page);
      if (token != _requestId) return;
      final items = replace
          ? response.items
          : _appendUnique(previous.items, response.items, (item) => item.id);
      state = DiagnosisHistoryState(
        status: items.isEmpty ? HistoryStatus.empty : HistoryStatus.data,
        items: items,
        currentPage: response.page,
        totalPages: response.totalPages,
        totalItems: response.totalItems,
        hasNext: response.hasNext,
        filter: previous.filter,
      );
    } on ApiException catch (error) {
      if (token != _requestId) return;
      if (error.isUnauthenticated) {
        await _expireSession();
        state = const DiagnosisHistoryState();
      } else if (!replace && previous.items.isNotEmpty) {
        state = _diagnosisWithMessage(previous, error.message);
      } else {
        state = DiagnosisHistoryState(
          status: HistoryStatus.error,
          filter: previous.filter,
          message: error.message,
          requestId: error.requestId,
        );
      }
    } catch (_) {
      state = DiagnosisHistoryState(
        status: HistoryStatus.error,
        filter: previous.filter,
        message: 'Không thể tải lịch sử phân tích.',
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _deleteError(
    ApiException error,
    DiagnosisHistoryState previous,
  ) async {
    if (error.isUnauthenticated) {
      await _expireSession();
      state = const DiagnosisHistoryState();
    } else {
      state = _diagnosisWithMessage(previous, error.message);
    }
  }

  DiagnosisHistoryState _diagnosisWithMessage(
    DiagnosisHistoryState value,
    String message,
  ) => DiagnosisHistoryState(
    status: value.items.isEmpty ? HistoryStatus.empty : HistoryStatus.data,
    items: value.items,
    currentPage: value.currentPage,
    totalPages: value.totalPages,
    totalItems: value.totalItems,
    hasNext: value.hasNext,
    filter: value.filter,
    message: message,
  );

  Future<void> _expireSession() => ref
      .read(authControllerProvider.notifier)
      .clearSessionAfterSensitiveChange(message: 'Phiên đăng nhập đã hết hạn.');
}

class ComparisonHistoryController extends Notifier<ComparisonHistoryState> {
  late HistoryRepository _repository;
  bool _busy = false;
  int _requestId = 0;

  @override
  ComparisonHistoryState build() {
    _repository = ref.watch(historyApiProvider);
    ref.listen<AuthState>(authControllerProvider, (_, next) {
      if (next.status != AuthStatus.authenticated) {
        _requestId++;
        state = const ComparisonHistoryState();
      }
    });
    return const ComparisonHistoryState();
  }

  Future<void> load({bool force = false}) async {
    if (_busy || (!force && state.status != HistoryStatus.idle)) return;
    await _fetch(0, replace: true, refreshing: false);
  }

  Future<void> refresh() => _fetch(0, replace: true, refreshing: true);

  Future<void> applyFilter(ComparisonHistoryFilter filter) async {
    if (filter.dateError != null) return;
    state = ComparisonHistoryState(filter: filter);
    await _fetch(0, replace: true, refreshing: false);
  }

  Future<void> search(String keyword) =>
      applyFilter(state.filter.copyWith(keyword: keyword));

  Future<void> clearSearch() => applyFilter(state.filter.copyWith(keyword: ''));

  Future<void> resetFilter() => applyFilter(const ComparisonHistoryFilter());

  Future<void> loadMore() async {
    if (_busy || !state.hasNext) return;
    await _fetch(state.currentPage + 1, replace: false, refreshing: false);
  }

  Future<bool> deleteItem(String groupId) async {
    if (_busy ||
        !state.items.any((item) => item.comparisonGroupId == groupId)) {
      return false;
    }
    _busy = true;
    final previous = state;
    state = _comparisonCopy(previous, status: HistoryStatus.deleting);
    try {
      await _repository.deleteComparison(groupId);
      final remaining = previous.items
          .where((item) => item.comparisonGroupId != groupId)
          .toList();
      state = ComparisonHistoryState(
        status: remaining.isEmpty ? HistoryStatus.empty : HistoryStatus.data,
        items: remaining,
        currentPage: previous.currentPage,
        totalPages: previous.totalPages,
        totalItems: (previous.totalItems - 1).clamp(0, 1 << 31),
        hasNext: previous.hasNext,
        filter: previous.filter,
      );
      ref.invalidate(dashboardControllerProvider);
      _busy = false;
      if (remaining.isEmpty && previous.currentPage > 0) {
        await _fetch(
          previous.currentPage - 1,
          replace: true,
          refreshing: false,
        );
      }
      return true;
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await _expireSession();
        state = const ComparisonHistoryState();
      } else if (error.statusCode == 404) {
        _busy = false;
        await _fetch(0, replace: true, refreshing: false);
      } else {
        state = _comparisonCopy(previous, message: error.message);
      }
      return false;
    } catch (_) {
      state = _comparisonCopy(
        previous,
        message: 'Không thể xóa phiên so sánh.',
      );
      return false;
    } finally {
      _busy = false;
    }
  }

  Future<void> _fetch(
    int page, {
    required bool replace,
    required bool refreshing,
  }) async {
    if (_busy) return;
    _busy = true;
    final token = ++_requestId;
    final previous = state;
    state = _comparisonCopy(
      previous,
      status: refreshing && previous.items.isNotEmpty
          ? HistoryStatus.refreshing
          : replace
          ? HistoryStatus.loading
          : HistoryStatus.loadingNextPage,
    );
    try {
      final response = await _repository.getComparisons(previous.filter, page);
      if (token != _requestId) return;
      final items = replace
          ? response.items
          : _appendUnique(
              previous.items,
              response.items,
              (item) => item.comparisonGroupId,
            );
      state = ComparisonHistoryState(
        status: items.isEmpty ? HistoryStatus.empty : HistoryStatus.data,
        items: items,
        currentPage: response.page,
        totalPages: response.totalPages,
        totalItems: response.totalItems,
        hasNext: response.hasNext,
        filter: previous.filter,
      );
    } on ApiException catch (error) {
      if (token != _requestId) return;
      if (error.isUnauthenticated) {
        await _expireSession();
        state = const ComparisonHistoryState();
      } else if (!replace && previous.items.isNotEmpty) {
        state = _comparisonCopy(previous, message: error.message);
      } else {
        state = ComparisonHistoryState(
          status: HistoryStatus.error,
          filter: previous.filter,
          message: error.message,
          requestId: error.requestId,
        );
      }
    } catch (_) {
      state = ComparisonHistoryState(
        status: HistoryStatus.error,
        filter: previous.filter,
        message: 'Không thể tải lịch sử so sánh.',
      );
    } finally {
      _busy = false;
    }
  }

  ComparisonHistoryState _comparisonCopy(
    ComparisonHistoryState value, {
    HistoryStatus? status,
    String? message,
  }) => ComparisonHistoryState(
    status:
        status ??
        (value.items.isEmpty ? HistoryStatus.empty : HistoryStatus.data),
    items: value.items,
    currentPage: value.currentPage,
    totalPages: value.totalPages,
    totalItems: value.totalItems,
    hasNext: value.hasNext,
    filter: value.filter,
    message: message,
  );

  Future<void> _expireSession() => ref
      .read(authControllerProvider.notifier)
      .clearSessionAfterSensitiveChange(message: 'Phiên đăng nhập đã hết hạn.');
}

List<T> _appendUnique<T>(
  List<T> existing,
  List<T> incoming,
  String Function(T item) id,
) {
  final seen = existing.map(id).toSet();
  return [...existing, ...incoming.where((item) => seen.add(id(item)))];
}
