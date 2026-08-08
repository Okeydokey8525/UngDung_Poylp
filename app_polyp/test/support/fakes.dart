import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_polyp/core/network/api_exception.dart';
import 'package:app_polyp/core/network/csrf_token.dart';
import 'package:app_polyp/core/network/network_providers.dart';
import 'package:app_polyp/features/account/account_api.dart';
import 'package:app_polyp/features/account/account_models.dart';
import 'package:app_polyp/features/auth/auth_api.dart';
import 'package:app_polyp/features/auth/auth_models.dart';
import 'package:app_polyp/features/dashboard/dashboard_api.dart';
import 'package:app_polyp/features/dashboard/dashboard_models.dart';
import 'package:app_polyp/features/comparison/comparison_api.dart';
import 'package:app_polyp/features/comparison/comparison_models.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_api.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_controller.dart';
import 'package:app_polyp/features/diagnosis/diagnosis_models.dart';
import 'package:app_polyp/features/history/history_api.dart';
import 'package:app_polyp/features/history/history_filters.dart';
import 'package:app_polyp/features/history/history_models.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

const testUser = AuthUser(
  id: 'user-1',
  fullName: 'Nguyễn Văn An',
  email: 'an@example.com',
  role: 'USER',
);

UserDashboard testDashboard() => UserDashboard(
  summary: const DashboardSummary(
    singleAnalysisCount: 3,
    comparisonSessionCount: 1,
    totalInferenceCount: 5,
    detectedCount: 4,
    notDetectedCount: 1,
    baselineCount: 3,
    vmambaCount: 2,
    averageProcessingTimeMs: 148.5,
    averageDetectedConfidence: 0.624,
    totalMaskCount: 7,
    detectedRate: 0.8,
    mostUsedModel: 'YOLO26n-seg',
  ),
  dailyUsage: [
    DailyUsage(date: DateTime(2026, 7, 25), count: 0),
    DailyUsage(date: DateTime(2026, 7, 26), count: 1),
    DailyUsage(date: DateTime(2026, 7, 27), count: 0),
    DailyUsage(date: DateTime(2026, 7, 28), count: 2),
    DailyUsage(date: DateTime(2026, 7, 29), count: 0),
    DailyUsage(date: DateTime(2026, 7, 30), count: 1),
    DailyUsage(date: DateTime(2026, 7, 31), count: 1),
  ],
  modelUsage: const ModelUsage(baseline: 3, vmamba: 2),
  predictionUsage: const PredictionUsage(detected: 4, notDetected: 1),
  recentActivities: [
    RecentActivity(
      id: 'diagnosis-1',
      type: RecentActivityType.diagnosis,
      fileName: 'sample.jpg',
      modelType: 'YOLO26n-seg',
      detected: true,
      confidence: 0.624,
      maskCount: 2,
      processingTimeMs: 148.5,
      createdAt: DateTime(2026, 7, 31, 9, 30),
    ),
  ],
  disclaimer:
      'Các thống kê này phản ánh hoạt động sử dụng hệ thống và kết quả '
      'dự đoán đã lưu, không thay thế đánh giá thực nghiệm khoa học '
      'của mô hình.',
);

const emptyDashboard = UserDashboard(
  summary: DashboardSummary(),
  dailyUsage: [],
  modelUsage: ModelUsage(),
  predictionUsage: PredictionUsage(),
  recentActivities: [],
  disclaimer:
      'Các thống kê này phản ánh hoạt động sử dụng hệ thống và kết quả '
      'dự đoán đã lưu, không thay thế đánh giá thực nghiệm khoa học '
      'của mô hình.',
);

DiagnosisResult testDiagnosisResult({
  String id = 'diagnosis-1',
  String modelType = 'YOLO26n-seg',
  String modelCategory = 'BASELINE',
}) => DiagnosisResult(
  id: id,
  fileName: 'sample.jpg',
  modelType: modelType,
  modelCategory: modelCategory,
  detected: true,
  label: 'polyp',
  confidence: 0.624,
  maskCount: 2,
  processingTimeMs: 148.5,
  createdAt: DateTime.utc(2026, 7, 31, 9, 30),
  originalImageUrl: '/api/v1/diagnoses/$id/images/original',
  resultImageUrl: '/api/v1/diagnoses/$id/images/result',
  metadataUrl: '/api/v1/diagnoses/$id/metadata',
);

ComparisonResult testComparisonResult({
  String groupId = 'comparison-group-1',
}) => ComparisonResult(
  comparisonGroupId: groupId,
  fileName: 'sample.png',
  createdAt: DateTime.utc(2026, 8, 1, 10),
  originalImageUrl: '/api/v1/diagnoses/baseline-id/images/original',
  baseline: const ComparisonModelResult(
    id: 'baseline-id',
    modelType: 'YOLO26n-seg',
    modelCategory: 'BASELINE',
    detected: true,
    label: 'polyp',
    confidence: 0.62,
    maskCount: 2,
    processingTimeMs: 148.5,
    resultImageUrl: '/api/v1/diagnoses/baseline-id/images/result',
  ),
  vmamba: const ComparisonModelResult(
    id: 'vmamba-id',
    modelType: 'YOLO26n-VMamba-seg',
    modelCategory: 'VMAMBA',
    detected: true,
    label: 'polyp',
    confidence: 0.67,
    maskCount: 3,
    processingTimeMs: 174.2,
    resultImageUrl: '/api/v1/diagnoses/vmamba-id/images/result',
  ),
  totalProcessingTimeMs: 322.7,
  metadataUrl: '/api/v1/comparisons/$groupId/metadata',
);

DiagnosisHistoryItem testDiagnosisHistoryItem({
  String id = 'diagnosis-1',
  String fileName = 'sample.jpg',
}) => DiagnosisHistoryItem(
  id: id,
  fileName: fileName,
  modelType: 'YOLO26n-seg',
  modelCategory: 'BASELINE',
  detected: true,
  label: 'polyp',
  confidence: 0.624,
  maskCount: 2,
  processingTimeMs: 148.5,
  createdAt: DateTime.utc(2026, 8, 1, 10),
  originalImageUrl: '/api/v1/diagnoses/$id/images/original',
  resultImageUrl: '/api/v1/diagnoses/$id/images/result',
);

ComparisonHistoryItem testComparisonHistoryItem({
  String groupId = 'comparison-group-1',
  String fileName = 'sample.png',
}) => ComparisonHistoryItem(
  comparisonGroupId: groupId,
  fileName: fileName,
  createdAt: DateTime.utc(2026, 8, 1, 10),
  originalImageUrl: '/api/v1/diagnoses/baseline-id/images/original',
  baseline: const ComparisonHistoryModelResult(
    id: 'baseline-id',
    detected: true,
    confidence: 0.62,
    maskCount: 2,
    processingTimeMs: 148.5,
    resultImageUrl: '/api/v1/diagnoses/baseline-id/images/result',
  ),
  vmamba: const ComparisonHistoryModelResult(
    id: 'vmamba-id',
    detected: true,
    confidence: 0.67,
    maskCount: 3,
    processingTimeMs: 174.2,
    resultImageUrl: '/api/v1/diagnoses/vmamba-id/images/result',
  ),
  totalProcessingTimeMs: 322.7,
);

class FakeHistoryApi implements HistoryRepository {
  Future<PagedResponse<DiagnosisHistoryItem>> Function(
    DiagnosisHistoryFilter filter,
    int page,
  )?
  onDiagnoses;
  Future<PagedResponse<ComparisonHistoryItem>> Function(
    ComparisonHistoryFilter filter,
    int page,
  )?
  onComparisons;
  Future<void> Function(String id)? onDeleteDiagnosis;
  Future<void> Function(String groupId)? onDeleteComparison;
  int diagnosisCalls = 0;
  int comparisonCalls = 0;
  int deleteDiagnosisCalls = 0;
  int deleteComparisonCalls = 0;
  DiagnosisHistoryFilter? lastDiagnosisFilter;
  ComparisonHistoryFilter? lastComparisonFilter;
  int? lastDiagnosisPage;
  int? lastComparisonPage;
  String? lastDeletedDiagnosisId;
  String? lastDeletedComparisonId;

  @override
  Future<PagedResponse<DiagnosisHistoryItem>> getDiagnoses(
    DiagnosisHistoryFilter filter,
    int page,
  ) {
    diagnosisCalls++;
    lastDiagnosisFilter = filter;
    lastDiagnosisPage = page;
    return onDiagnoses?.call(filter, page) ??
        Future.value(
          PagedResponse(
            items: [testDiagnosisHistoryItem()],
            page: page,
            size: filter.size,
            totalItems: 1,
            totalPages: 1,
            hasNext: false,
            hasPrevious: page > 0,
          ),
        );
  }

  @override
  Future<PagedResponse<ComparisonHistoryItem>> getComparisons(
    ComparisonHistoryFilter filter,
    int page,
  ) {
    comparisonCalls++;
    lastComparisonFilter = filter;
    lastComparisonPage = page;
    return onComparisons?.call(filter, page) ??
        Future.value(
          PagedResponse(
            items: [testComparisonHistoryItem()],
            page: page,
            size: filter.size,
            totalItems: 1,
            totalPages: 1,
            hasNext: false,
            hasPrevious: page > 0,
          ),
        );
  }

  @override
  Future<void> deleteDiagnosis(String id) {
    deleteDiagnosisCalls++;
    lastDeletedDiagnosisId = id;
    return onDeleteDiagnosis?.call(id) ?? Future.value();
  }

  @override
  Future<void> deleteComparison(String comparisonGroupId) {
    deleteComparisonCalls++;
    lastDeletedComparisonId = comparisonGroupId;
    return onDeleteComparison?.call(comparisonGroupId) ?? Future.value();
  }
}

class FakeComparisonApi implements ComparisonRepository {
  Future<ComparisonResult> Function(
    SelectedDiagnosisImage image,
    UploadProgressCallback? onProgress,
  )?
  onCreate;
  Future<ComparisonResult> Function(String groupId)? onGet;
  Future<void> Function(String groupId)? onDelete;
  int createCalls = 0;
  int getCalls = 0;
  int deleteCalls = 0;
  String? lastDeletedGroupId;

  @override
  Future<ComparisonResult> createComparison(
    SelectedDiagnosisImage image, {
    UploadProgressCallback? onSendProgress,
  }) {
    createCalls++;
    return onCreate?.call(image, onSendProgress) ??
        Future.value(testComparisonResult());
  }

  @override
  Future<void> deleteComparison(String comparisonGroupId) {
    deleteCalls++;
    lastDeletedGroupId = comparisonGroupId;
    return onDelete?.call(comparisonGroupId) ?? Future.value();
  }

  @override
  Future<ComparisonResult> getComparison(String comparisonGroupId) {
    getCalls++;
    return onGet?.call(comparisonGroupId) ??
        Future.value(testComparisonResult(groupId: comparisonGroupId));
  }
}

SelectedDiagnosisImage testSelectedImage({
  String name = 'sample.png',
  String mimeType = 'image/png',
  int? sizeBytes,
}) => SelectedDiagnosisImage(
  file: XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
    name: name,
    mimeType: mimeType,
  ),
  name: name,
  mimeType: mimeType,
  sizeBytes:
      sizeBytes ??
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ).length,
);

class FakeDiagnosisApi implements DiagnosisRepository {
  Future<DiagnosisResult> Function(
    SelectedDiagnosisImage image,
    DiagnosisModelOption model,
    UploadProgressCallback? onProgress,
  )?
  onCreate;
  Future<DiagnosisResult> Function(String id)? onGet;
  Future<Uint8List> Function(String url)? onLoadImage;
  Future<void> Function(String id)? onDelete;
  int createCalls = 0;
  int getCalls = 0;
  int imageCalls = 0;
  int deleteCalls = 0;
  DiagnosisModelOption? lastModel;

  @override
  Future<DiagnosisResult> createDiagnosis(
    SelectedDiagnosisImage image,
    DiagnosisModelOption model, {
    UploadProgressCallback? onSendProgress,
  }) {
    createCalls++;
    lastModel = model;
    return onCreate?.call(image, model, onSendProgress) ??
        Future.value(testDiagnosisResult(modelType: model.apiValue));
  }

  @override
  Future<void> deleteDiagnosis(String id) {
    deleteCalls++;
    return onDelete?.call(id) ?? Future.value();
  }

  @override
  Future<DiagnosisResult> getDiagnosis(String id) {
    getCalls++;
    return onGet?.call(id) ?? Future.value(testDiagnosisResult(id: id));
  }

  @override
  Future<Uint8List> loadImage(String url) {
    imageCalls++;
    return onLoadImage?.call(url) ??
        Future.value(
          Uint8List.fromList(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
            ),
          ),
        );
  }
}

class FakeDiagnosisImagePicker implements DiagnosisImagePicker {
  SelectedDiagnosisImage? selected = testSelectedImage();
  Object? error;
  int calls = 0;

  @override
  Future<SelectedDiagnosisImage?> pickFromGallery() async {
    calls++;
    if (error != null) throw error!;
    return selected;
  }
}

class FakeAuthApi implements AuthRepository {
  Future<AuthUser> Function()? onMe;
  Future<AuthUser> Function(LoginRequest request)? onLogin;
  Future<RegisterResult> Function(RegisterRequest request)? onRegister;
  Future<void> Function()? onLogout;
  int meCalls = 0;
  int loginCalls = 0;
  int registerCalls = 0;
  int logoutCalls = 0;
  int csrfCalls = 0;
  LoginRequest? lastLogin;
  RegisterRequest? lastRegister;

  @override
  Future<CsrfToken> fetchCsrf() async {
    csrfCalls++;
    return const CsrfToken(
      token: 'csrf-token',
      headerName: 'X-CSRF-TOKEN',
      parameterName: '_csrf',
    );
  }

  @override
  Future<AuthUser> login(LoginRequest request) {
    loginCalls++;
    lastLogin = request;
    return onLogin?.call(request) ?? Future.value(testUser);
  }

  @override
  Future<void> logout() {
    logoutCalls++;
    return onLogout?.call() ?? Future.value();
  }

  @override
  Future<AuthUser> me() {
    meCalls++;
    return onMe?.call() ??
        Future.error(
          const ApiException(
            statusCode: 401,
            code: 'UNAUTHENTICATED',
            message: 'Phiên đăng nhập đã hết hạn.',
          ),
        );
  }

  @override
  Future<RegisterResult> register(RegisterRequest request) {
    registerCalls++;
    lastRegister = request;
    return onRegister?.call(request) ??
        Future.value(
          RegisterResult(
            message: 'Đăng ký thành công.',
            email: request.email.trim().toLowerCase(),
          ),
        );
  }
}

class FakeDashboardApi implements DashboardRepository {
  Future<UserDashboard> Function()? onFetch;
  int fetchCalls = 0;

  @override
  Future<UserDashboard> fetchDashboard() {
    fetchCalls++;
    return onFetch?.call() ?? Future.value(emptyDashboard);
  }
}

class FakeAccountApi implements AccountRepository {
  Future<ProfileUpdateResult> Function(ProfileUpdateRequest request)?
  onUpdateProfile;
  Future<void> Function(PasswordChangeRequest request)? onChangePassword;
  int updateProfileCalls = 0;
  int changePasswordCalls = 0;
  ProfileUpdateRequest? lastProfileRequest;
  PasswordChangeRequest? lastPasswordRequest;

  @override
  Future<void> changePassword(PasswordChangeRequest request) {
    changePasswordCalls++;
    lastPasswordRequest = request;
    return onChangePassword?.call(request) ?? Future.value();
  }

  @override
  Future<ProfileUpdateResult> updateProfile(ProfileUpdateRequest request) {
    updateProfileCalls++;
    lastProfileRequest = request;
    return onUpdateProfile?.call(request) ??
        Future.value(
          const ProfileUpdateResult(
            user: testUser,
            reauthenticationRequired: false,
          ),
        );
  }
}

class FakeSessionStore implements AuthSessionStore {
  int clearAllCalls = 0;
  int clearCsrfCalls = 0;
  void Function()? unauthorizedHandler;

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
  }

  @override
  void clearCsrf() {
    clearCsrfCalls++;
  }

  @override
  void setUnauthorizedHandler(void Function()? handler) {
    unauthorizedHandler = handler;
  }
}

typedef AdapterHandler = ResponseBody Function(RequestOptions options);

class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter(this.handler);

  final AdapterHandler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(
  Object body, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      ...?headers,
    },
  );
}
