import 'package:app_polyp/features/history/history_filters.dart';
import 'package:app_polyp/features/history/history_models.dart';

enum HistoryStatus {
  idle,
  loading,
  data,
  empty,
  error,
  refreshing,
  loadingNextPage,
  deleting,
}

class DiagnosisHistoryState {
  const DiagnosisHistoryState({
    this.status = HistoryStatus.idle,
    this.items = const [],
    this.currentPage = 0,
    this.totalPages = 0,
    this.totalItems = 0,
    this.hasNext = false,
    this.filter = const DiagnosisHistoryFilter(),
    this.message,
    this.requestId,
  });

  final HistoryStatus status;
  final List<DiagnosisHistoryItem> items;
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final bool hasNext;
  final DiagnosisHistoryFilter filter;
  final String? message;
  final String? requestId;
}

class ComparisonHistoryState {
  const ComparisonHistoryState({
    this.status = HistoryStatus.idle,
    this.items = const [],
    this.currentPage = 0,
    this.totalPages = 0,
    this.totalItems = 0,
    this.hasNext = false,
    this.filter = const ComparisonHistoryFilter(),
    this.message,
    this.requestId,
  });

  final HistoryStatus status;
  final List<ComparisonHistoryItem> items;
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final bool hasNext;
  final ComparisonHistoryFilter filter;
  final String? message;
  final String? requestId;
}
