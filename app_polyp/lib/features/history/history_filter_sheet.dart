import 'package:app_polyp/features/history/history_filters.dart';
import 'package:flutter/material.dart';

Future<DiagnosisHistoryFilter?> showDiagnosisHistoryFilterSheet(
  BuildContext context,
  DiagnosisHistoryFilter initial,
) => showModalBottomSheet<DiagnosisHistoryFilter>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _DiagnosisFilterSheet(initial: initial),
);

Future<ComparisonHistoryFilter?> showComparisonHistoryFilterSheet(
  BuildContext context,
  ComparisonHistoryFilter initial,
) => showModalBottomSheet<ComparisonHistoryFilter>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => _ComparisonFilterSheet(initial: initial),
);

class _DiagnosisFilterSheet extends StatefulWidget {
  const _DiagnosisFilterSheet({required this.initial});
  final DiagnosisHistoryFilter initial;

  @override
  State<_DiagnosisFilterSheet> createState() => _DiagnosisFilterSheetState();
}

class _DiagnosisFilterSheetState extends State<_DiagnosisFilterSheet> {
  late DiagnosisHistoryFilter value = widget.initial;

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: 'Lọc lịch sử phân tích',
    dateError: value.dateError,
    onReset: () => Navigator.pop(context, const DiagnosisHistoryFilter()),
    onApply: value.dateError == null
        ? () => Navigator.pop(context, value)
        : null,
    children: [
      _Dropdown(
        key: const Key('diagnosis-filter-model'),
        label: 'Mô hình',
        value: value.model,
        values: const {
          'ALL': 'Tất cả mô hình',
          'YOLO26n-seg': 'YOLO26n-seg',
          'YOLO26n-VMamba-seg': 'YOLO26n-VMamba-seg',
        },
        onChanged: (next) =>
            setState(() => value = value.copyWith(model: next)),
      ),
      _Dropdown(
        key: const Key('diagnosis-filter-detected'),
        label: 'Trạng thái',
        value: value.detected,
        values: const {
          'ALL': 'Tất cả',
          'true': 'Có phát hiện',
          'false': 'Không phát hiện',
        },
        onChanged: (next) =>
            setState(() => value = value.copyWith(detected: next)),
      ),
      _DateRange(
        from: value.dateFrom,
        to: value.dateTo,
        onFrom: (date) => setState(
          () => value = value.copyWith(
            dateFrom: date,
            clearDateFrom: date == null,
          ),
        ),
        onTo: (date) => setState(
          () => value = value.copyWith(dateTo: date, clearDateTo: date == null),
        ),
      ),
      _Dropdown(
        key: const Key('diagnosis-filter-sort'),
        label: 'Sắp xếp',
        value: value.sort,
        values: const {
          'newest': 'Mới nhất',
          'oldest': 'Cũ nhất',
          'confidence-desc': 'Confidence giảm dần',
          'confidence-asc': 'Confidence tăng dần',
          'processing-desc': 'Xử lý lâu nhất',
          'processing-asc': 'Xử lý nhanh nhất',
        },
        onChanged: (next) => setState(() => value = value.copyWith(sort: next)),
      ),
      _PageSize(
        value: value.size,
        onChanged: (next) => setState(() => value = value.copyWith(size: next)),
      ),
    ],
  );
}

class _ComparisonFilterSheet extends StatefulWidget {
  const _ComparisonFilterSheet({required this.initial});
  final ComparisonHistoryFilter initial;

  @override
  State<_ComparisonFilterSheet> createState() => _ComparisonFilterSheetState();
}

class _ComparisonFilterSheetState extends State<_ComparisonFilterSheet> {
  late ComparisonHistoryFilter value = widget.initial;

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: 'Lọc lịch sử so sánh',
    dateError: value.dateError,
    onReset: () => Navigator.pop(context, const ComparisonHistoryFilter()),
    onApply: value.dateError == null
        ? () => Navigator.pop(context, value)
        : null,
    children: [
      _Dropdown(
        key: const Key('comparison-filter-baseline'),
        label: 'Baseline',
        value: value.baselineDetected,
        values: const {
          'ALL': 'Tất cả',
          'true': 'Có phát hiện',
          'false': 'Không phát hiện',
        },
        onChanged: (next) =>
            setState(() => value = value.copyWith(baselineDetected: next)),
      ),
      _Dropdown(
        key: const Key('comparison-filter-vmamba'),
        label: 'VMamba',
        value: value.vmambaDetected,
        values: const {
          'ALL': 'Tất cả',
          'true': 'Có phát hiện',
          'false': 'Không phát hiện',
        },
        onChanged: (next) =>
            setState(() => value = value.copyWith(vmambaDetected: next)),
      ),
      _DateRange(
        from: value.dateFrom,
        to: value.dateTo,
        onFrom: (date) => setState(
          () => value = value.copyWith(
            dateFrom: date,
            clearDateFrom: date == null,
          ),
        ),
        onTo: (date) => setState(
          () => value = value.copyWith(dateTo: date, clearDateTo: date == null),
        ),
      ),
      _Dropdown(
        key: const Key('comparison-filter-sort'),
        label: 'Sắp xếp',
        value: value.sort,
        values: const {
          'newest': 'Mới nhất',
          'oldest': 'Cũ nhất',
          'baseline-confidence-desc': 'Baseline confidence giảm dần',
          'vmamba-confidence-desc': 'VMamba confidence giảm dần',
          'total-processing-desc': 'Tổng xử lý lâu nhất',
          'total-processing-asc': 'Tổng xử lý nhanh nhất',
        },
        onChanged: (next) => setState(() => value = value.copyWith(sort: next)),
      ),
      _PageSize(
        value: value.size,
        onChanged: (next) => setState(() => value = value.copyWith(size: next)),
      ),
    ],
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.children,
    required this.onReset,
    required this.onApply,
    this.dateError,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback onReset;
  final VoidCallback? onApply;
  final String? dateError;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...children.expand((child) => [child, const SizedBox(height: 14)]),
          if (dateError != null)
            Text(
              dateError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('history-filter-reset'),
                  onPressed: onReset,
                  child: const Text('Đặt lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('history-filter-apply'),
                  onPressed: onApply,
                  child: const Text('Áp dụng'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    super.key,
  });
  final String label;
  final String value;
  final Map<String, String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: values.entries
        .map(
          (item) => DropdownMenuItem(value: item.key, child: Text(item.value)),
        )
        .toList(),
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class _PageSize extends StatelessWidget {
  const _PageSize({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    key: const Key('history-filter-size'),
    initialValue: value,
    decoration: const InputDecoration(labelText: 'Số bản ghi mỗi trang'),
    items: const [10, 20, 50]
        .map((size) => DropdownMenuItem(value: size, child: Text('$size')))
        .toList(),
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class _DateRange extends StatelessWidget {
  const _DateRange({
    required this.from,
    required this.to,
    required this.onFrom,
    required this.onTo,
  });
  final DateTime? from;
  final DateTime? to;
  final ValueChanged<DateTime?> onFrom;
  final ValueChanged<DateTime?> onTo;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _DateButton(label: 'Từ ngày', value: from, onChanged: onFrom),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _DateButton(label: 'Đến ngày', value: to, onChanged: onTo),
      ),
    ],
  );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: OutlinedButton.icon(
      onPressed: () async {
        final selected = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
          helpText: label,
        );
        if (selected != null) onChanged(selected);
      },
      onLongPress: value == null ? null : () => onChanged(null),
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(
        value == null ? label : '${value!.day}/${value!.month}/${value!.year}',
      ),
    ),
  );
}
