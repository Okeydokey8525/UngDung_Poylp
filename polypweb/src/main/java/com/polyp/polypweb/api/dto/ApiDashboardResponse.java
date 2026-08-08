package com.polyp.polypweb.api.dto;

import com.polyp.polypweb.view.RecentActivityView;
import com.polyp.polypweb.view.UserDashboardView;

import java.util.List;

public record ApiDashboardResponse(
        ApiDashboardSummaryResponse summary,
        List<ApiDailyUsageResponse> dailyUsage,
        ApiModelUsageResponse modelUsage,
        ApiPredictionUsageResponse predictionUsage,
        List<ApiRecentActivityResponse> recentActivities,
        String disclaimer
) {

    private static final String DISCLAIMER =
            "Các thống kê này phản ánh hoạt động sử dụng hệ thống và kết quả dự đoán "
                    + "đã lưu, không thay thế đánh giá thực nghiệm khoa học của mô hình.";

    public ApiDashboardResponse {
        dailyUsage = dailyUsage == null ? List.of() : List.copyOf(dailyUsage);
        recentActivities = recentActivities == null
                ? List.of()
                : List.copyOf(recentActivities);
    }

    public static ApiDashboardResponse from(UserDashboardView view) {
        String mostUsedModel = view.isEmpty()
                || view.getMostUsedModel() == null
                || view.getMostUsedModel().isBlank()
                || "Chưa có dữ liệu".equals(view.getMostUsedModel())
                ? null
                : view.getMostUsedModel();
        return new ApiDashboardResponse(
                new ApiDashboardSummaryResponse(
                        view.getSingleAnalysis(),
                        view.getComparisonSessions(),
                        view.getTotalInference(),
                        view.getDetected(),
                        view.getNotDetected(),
                        view.getBaselineUsage(),
                        view.getVmambaUsage(),
                        nonNegative(view.getAverageProcessingTimeMs()),
                        confidenceRatio(view.getAverageDetectedConfidence()),
                        view.getTotalMasks(),
                        clampRatio(view.getDetectedRate() / 100.0),
                        mostUsedModel
                ),
                view.getDailyUsage()
                        .stream()
                        .map(day -> new ApiDailyUsageResponse(day.getDate(), day.getCount()))
                        .toList(),
                new ApiModelUsageResponse(
                        view.getBaselineUsage(),
                        view.getVmambaUsage()
                ),
                new ApiPredictionUsageResponse(
                        view.getDetected(),
                        view.getNotDetected()
                ),
                view.getRecentActivities()
                        .stream()
                        .map(ApiDashboardResponse::recentActivity)
                        .toList(),
                DISCLAIMER
        );
    }

    private static ApiRecentActivityResponse recentActivity(RecentActivityView activity) {
        boolean comparison = activity.getComparisonGroupId() != null
                && !activity.getComparisonGroupId().isBlank();
        String id = activity.getId();
        String originalImageUrl = id == null || id.isBlank()
                ? null
                : "/diagnoses/" + id + "/original-image";
        return new ApiRecentActivityResponse(
                id,
                comparison ? "COMPARISON" : "DIAGNOSIS",
                safe(activity.getFileName()),
                safe(activity.getModelLabel()),
                activity.isDetected(),
                activity.isDetected() ? confidenceRatio(activity.getConfidence()) : 0,
                Math.max(0, activity.getMaskCount()),
                nonNegative(activity.getProcessingTimeMs()),
                activity.getCreatedAt(),
                comparison ? activity.getComparisonGroupId() : null,
                originalImageUrl
        );
    }

    private static double confidenceRatio(double value) {
        return clampRatio(value > 1 ? value / 100.0 : value);
    }

    private static double clampRatio(double value) {
        if (!Double.isFinite(value)) {
            return 0;
        }
        return Math.max(0, Math.min(1, value));
    }

    private static double nonNegative(double value) {
        return Double.isFinite(value) ? Math.max(0, value) : 0;
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}
