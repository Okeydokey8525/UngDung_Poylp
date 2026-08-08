import 'package:app_polyp/features/history/history_controller.dart';
import 'package:app_polyp/features/history/history_filter_sheet.dart';
import 'package:app_polyp/features/history/history_models.dart';
import 'package:app_polyp/features/history/history_state.dart';
import 'package:app_polyp/navigation/app_routes.dart';
import 'package:app_polyp/shared/widgets/app_card.dart';
import 'package:app_polyp/shared/widgets/app_empty_state.dart';
import 'package:app_polyp/shared/widgets/app_error_state.dart';
import 'package:app_polyp/shared/widgets/app_loading_view.dart';
import 'package:app_polyp/shared/widgets/app_section_header.dart';
import 'package:app_polyp/shared/widgets/app_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTab);
    Future<void>.microtask(() {
      ref.read(diagnosisHistoryControllerProvider.notifier).load();
      ref.read(comparisonHistoryControllerProvider.notifier).load();
    });
  }

  void _onTab() {
    if (_tabs.indexIsChanging || _active == _tabs.index) return;
    setState(() {
      _active = _tabs.index;
      _search.text = _active == 0
          ? ref.read(diagnosisHistoryControllerProvider).filter.keyword
          : ref.read(comparisonHistoryControllerProvider).filter.keyword;
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis = ref.watch(diagnosisHistoryControllerProvider);
    final comparison = ref.watch(comparisonHistoryControllerProvider);
    final count = _active == 0
        ? diagnosis.filter.activeCount
        : comparison.filter.activeCount;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: AppSectionHeader(
            title: 'Lịch sử',
            subtitle: 'Dữ liệu phân tích và so sánh đã lưu của tài khoản.',
            action: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: IconButton.outlined(
                key: const Key('history-filter-button'),
                tooltip: 'Lọc lịch sử',
                onPressed: _openFilter,
                icon: const Icon(Icons.filter_list),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: TextField(
              key: const Key('history-search'),
              controller: _search,
              maxLength: 100,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'Tìm theo tên file',
                counterText: '',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_search.text.isNotEmpty)
                      IconButton(
                        key: const Key('history-search-clear'),
                        tooltip: 'Xóa từ khóa',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close),
                      ),
                    IconButton(
                      key: const Key('history-search-submit'),
                      tooltip: 'Tìm kiếm',
                      onPressed: _submitSearch,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submitSearch(),
            ),
          ),
        ),
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Phân tích'),
            Tab(text: 'So sánh'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [_DiagnosisList(), _ComparisonList()],
          ),
        ),
      ],
    );
  }

  Future<void> _submitSearch() async {
    FocusScope.of(context).unfocus();
    if (_active == 0) {
      await ref
          .read(diagnosisHistoryControllerProvider.notifier)
          .search(_search.text);
    } else {
      await ref
          .read(comparisonHistoryControllerProvider.notifier)
          .search(_search.text);
    }
  }

  Future<void> _clearSearch() async {
    _search.clear();
    setState(() {});
    if (_active == 0) {
      await ref.read(diagnosisHistoryControllerProvider.notifier).clearSearch();
    } else {
      await ref
          .read(comparisonHistoryControllerProvider.notifier)
          .clearSearch();
    }
  }

  Future<void> _openFilter() async {
    if (_active == 0) {
      final result = await showDiagnosisHistoryFilterSheet(
        context,
        ref.read(diagnosisHistoryControllerProvider).filter,
      );
      if (result != null) {
        await ref
            .read(diagnosisHistoryControllerProvider.notifier)
            .applyFilter(result);
      }
    } else {
      final result = await showComparisonHistoryFilterSheet(
        context,
        ref.read(comparisonHistoryControllerProvider).filter,
      );
      if (result != null) {
        await ref
            .read(comparisonHistoryControllerProvider.notifier)
            .applyFilter(result);
      }
    }
  }
}

class _DiagnosisList extends ConsumerWidget {
  const _DiagnosisList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(diagnosisHistoryControllerProvider);
    return _HistoryBody<DiagnosisHistoryItem>(
      status: state.status,
      items: state.items,
      hasNext: state.hasNext,
      totalItems: state.totalItems,
      message: state.message,
      emptyTitle: 'Chưa có lịch sử phân tích',
      onRefresh: ref.read(diagnosisHistoryControllerProvider.notifier).refresh,
      onRetry: () => ref
          .read(diagnosisHistoryControllerProvider.notifier)
          .load(force: true),
      onLoadMore: ref
          .read(diagnosisHistoryControllerProvider.notifier)
          .loadMore,
      itemBuilder: (item) => _DiagnosisCard(
        item: item,
        onDelete: () => _deleteDiagnosis(context, ref, item),
      ),
    );
  }
}

class _ComparisonList extends ConsumerWidget {
  const _ComparisonList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(comparisonHistoryControllerProvider);
    return _HistoryBody<ComparisonHistoryItem>(
      status: state.status,
      items: state.items,
      hasNext: state.hasNext,
      totalItems: state.totalItems,
      message: state.message,
      emptyTitle: 'Chưa có lịch sử so sánh',
      onRefresh: ref.read(comparisonHistoryControllerProvider.notifier).refresh,
      onRetry: () => ref
          .read(comparisonHistoryControllerProvider.notifier)
          .load(force: true),
      onLoadMore: ref
          .read(comparisonHistoryControllerProvider.notifier)
          .loadMore,
      itemBuilder: (item) => _ComparisonCard(
        item: item,
        onDelete: () => _deleteComparison(context, ref, item),
      ),
    );
  }
}

class _HistoryBody<T> extends StatelessWidget {
  const _HistoryBody({
    required this.status,
    required this.items,
    required this.hasNext,
    required this.totalItems,
    required this.message,
    required this.emptyTitle,
    required this.onRefresh,
    required this.onRetry,
    required this.onLoadMore,
    required this.itemBuilder,
  });
  final HistoryStatus status;
  final List<T> items;
  final bool hasNext;
  final int totalItems;
  final String? message;
  final String emptyTitle;
  final RefreshCallback onRefresh;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    if (status == HistoryStatus.idle || status == HistoryStatus.loading) {
      return const AppLoadingView(message: 'Đang tải lịch sử…');
    }
    if (status == HistoryStatus.error) {
      return AppErrorState(
        title: 'Không thể tải lịch sử',
        message: message ?? 'Vui lòng thử lại.',
        onRetry: onRetry,
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: items.isEmpty ? 1 : items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: items.isEmpty
                ? AppEmptyState(
                    title: emptyTitle,
                    message: 'Không có dữ liệu phù hợp với bộ lọc hiện tại.',
                    icon: Icons.history_outlined,
                  )
                : index < items.length
                ? itemBuilder(items[index])
                : _LoadMore(
                    hasNext: hasNext,
                    loading: status == HistoryStatus.loadingNextPage,
                    totalItems: totalItems,
                    onPressed: onLoadMore,
                  ),
          ),
        ),
      ),
    );
  }
}

class _DiagnosisCard extends StatelessWidget {
  const _DiagnosisCard({required this.item, required this.onDelete});
  final DiagnosisHistoryItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${item.fileName}, ${item.modelType}, ${item.detected ? 'có phát hiện' : 'không phát hiện'}',
    button: true,
    child: AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.push(AppRoutes.diagnosisResult(item.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.image_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.fileName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(item.modelType),
                      ],
                    ),
                  ),
                  IconButton(
                    key: Key('delete-diagnosis-${item.id}'),
                    tooltip: 'Xóa kết quả phân tích',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AppStatusBadge(
                    status: item.detected
                        ? AppStatus.detected
                        : AppStatus.clear,
                    text: item.detected ? 'Có phát hiện' : 'Không phát hiện',
                  ),
                  _Metric('Confidence ${_percent(item.confidence)}'),
                  _Metric('${item.maskCount} mask'),
                  _Metric('${item.processingTimeMs.toStringAsFixed(1)} ms'),
                ],
              ),
              const SizedBox(height: 8),
              Text(_dateText(item.createdAt)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({required this.item, required this.onDelete});
  final ComparisonHistoryItem item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${item.fileName}, phiên so sánh Baseline và VMamba',
    button: true,
    child: AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () =>
            context.push(AppRoutes.comparisonResult(item.comparisonGroupId)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.compare_outlined, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.fileName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: Key('delete-comparison-${item.comparisonGroupId}'),
                    tooltip: 'Xóa phiên so sánh',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ModelLine(name: 'Baseline', result: item.baseline),
              const SizedBox(height: 8),
              _ModelLine(name: 'VMamba', result: item.vmamba),
              const Divider(height: 20),
              Text(
                'Tổng hai lượt inference tuần tự: '
                '${item.totalProcessingTimeMs.toStringAsFixed(1)} ms',
              ),
              Text(_dateText(item.createdAt)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ModelLine extends StatelessWidget {
  const _ModelLine({required this.name, required this.result});
  final String name;
  final ComparisonHistoryModelResult result;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      AppStatusBadge(
        status: result.detected ? AppStatus.detected : AppStatus.clear,
        text: result.detected ? 'Có phát hiện' : 'Không phát hiện',
      ),
      Text(_percent(result.confidence)),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Chip(label: Text(text));
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({
    required this.hasNext,
    required this.loading,
    required this.totalItems,
    required this.onPressed,
  });
  final bool hasNext;
  final bool loading;
  final int totalItems;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    label: loading ? 'Đang tải thêm lịch sử' : 'Tổng $totalItems bản ghi',
    child: Center(
      child: hasNext
          ? OutlinedButton.icon(
              key: const Key('history-load-more'),
              onPressed: loading ? null : onPressed,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(loading ? 'Đang tải…' : 'Tải thêm'),
            )
          : Text('Đã hiển thị $totalItems bản ghi'),
    ),
  );
}

Future<void> _deleteDiagnosis(
  BuildContext context,
  WidgetRef ref,
  DiagnosisHistoryItem item,
) async {
  if (!await _confirm(
    context,
    'Xóa kết quả phân tích?',
    'Ảnh gốc, ảnh kết quả và bản ghi lịch sử này sẽ bị xóa.',
  )) {
    return;
  }
  final deleted = await ref
      .read(diagnosisHistoryControllerProvider.notifier)
      .deleteItem(item.id);
  if (context.mounted) _notify(context, deleted, 'Đã xóa kết quả phân tích.');
}

Future<void> _deleteComparison(
  BuildContext context,
  WidgetRef ref,
  ComparisonHistoryItem item,
) async {
  if (!await _confirm(
    context,
    'Xóa phiên so sánh?',
    'Ảnh gốc, hai overlay và hai bản ghi của phiên này sẽ bị xóa.',
  )) {
    return;
  }
  final deleted = await ref
      .read(comparisonHistoryControllerProvider.notifier)
      .deleteItem(item.comparisonGroupId);
  if (context.mounted) _notify(context, deleted, 'Đã xóa phiên so sánh.');
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            key: const Key('history-delete-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    ) ??
    false;

void _notify(BuildContext context, bool success, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(success ? message : 'Không thể xóa. Vui lòng thử lại.'),
    ),
  );
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

String _dateText(DateTime? value) {
  if (value == null) return 'Không rõ thời gian';
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')} · '
      '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}
