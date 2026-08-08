String? _dateValue(DateTime? value) => value == null
    ? null
    : '${value.year.toString().padLeft(4, '0')}-'
          '${value.month.toString().padLeft(2, '0')}-'
          '${value.day.toString().padLeft(2, '0')}';

class DiagnosisHistoryFilter {
  const DiagnosisHistoryFilter({
    this.keyword = '',
    this.model = 'ALL',
    this.detected = 'ALL',
    this.dateFrom,
    this.dateTo,
    this.sort = 'newest',
    this.size = 10,
  });

  final String keyword;
  final String model;
  final String detected;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String sort;
  final int size;

  int get activeCount => [
    keyword.trim().isNotEmpty,
    model != 'ALL',
    detected != 'ALL',
    dateFrom != null,
    dateTo != null,
    sort != 'newest',
    size != 10,
  ].where((active) => active).length;

  String? get dateError =>
      dateFrom != null && dateTo != null && dateFrom!.isAfter(dateTo!)
      ? 'Ngày bắt đầu không được sau ngày kết thúc.'
      : null;

  Map<String, dynamic> query(int page) => {
    'page': page,
    'size': size,
    if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    'model': model,
    'detected': detected,
    if (dateFrom != null) 'dateFrom': _dateValue(dateFrom),
    if (dateTo != null) 'dateTo': _dateValue(dateTo),
    'sort': sort,
  };

  DiagnosisHistoryFilter copyWith({
    String? keyword,
    String? model,
    String? detected,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? sort,
    int? size,
    bool clearDateFrom = false,
    bool clearDateTo = false,
  }) => DiagnosisHistoryFilter(
    keyword: (keyword ?? this.keyword).trim().substring(
      0,
      (keyword ?? this.keyword).trim().length.clamp(0, 100),
    ),
    model: model ?? this.model,
    detected: detected ?? this.detected,
    dateFrom: clearDateFrom ? null : dateFrom ?? this.dateFrom,
    dateTo: clearDateTo ? null : dateTo ?? this.dateTo,
    sort: sort ?? this.sort,
    size: size ?? this.size,
  );
}

class ComparisonHistoryFilter {
  const ComparisonHistoryFilter({
    this.keyword = '',
    this.baselineDetected = 'ALL',
    this.vmambaDetected = 'ALL',
    this.dateFrom,
    this.dateTo,
    this.sort = 'newest',
    this.size = 10,
  });

  final String keyword;
  final String baselineDetected;
  final String vmambaDetected;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String sort;
  final int size;

  int get activeCount => [
    keyword.trim().isNotEmpty,
    baselineDetected != 'ALL',
    vmambaDetected != 'ALL',
    dateFrom != null,
    dateTo != null,
    sort != 'newest',
    size != 10,
  ].where((active) => active).length;

  String? get dateError =>
      dateFrom != null && dateTo != null && dateFrom!.isAfter(dateTo!)
      ? 'Ngày bắt đầu không được sau ngày kết thúc.'
      : null;

  Map<String, dynamic> query(int page) => {
    'page': page,
    'size': size,
    if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
    'baselineDetected': baselineDetected,
    'vmambaDetected': vmambaDetected,
    if (dateFrom != null) 'dateFrom': _dateValue(dateFrom),
    if (dateTo != null) 'dateTo': _dateValue(dateTo),
    'sort': sort,
  };

  ComparisonHistoryFilter copyWith({
    String? keyword,
    String? baselineDetected,
    String? vmambaDetected,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? sort,
    int? size,
    bool clearDateFrom = false,
    bool clearDateTo = false,
  }) {
    final value = (keyword ?? this.keyword).trim();
    return ComparisonHistoryFilter(
      keyword: value.substring(0, value.length.clamp(0, 100)),
      baselineDetected: baselineDetected ?? this.baselineDetected,
      vmambaDetected: vmambaDetected ?? this.vmambaDetected,
      dateFrom: clearDateFrom ? null : dateFrom ?? this.dateFrom,
      dateTo: clearDateTo ? null : dateTo ?? this.dateTo,
      sort: sort ?? this.sort,
      size: size ?? this.size,
    );
  }
}
