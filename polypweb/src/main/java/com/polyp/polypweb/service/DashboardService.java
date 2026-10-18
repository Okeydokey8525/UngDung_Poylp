package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.repository.DashboardStatisticsRepository;
import com.polyp.polypweb.repository.DashboardStatisticsSnapshot;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.UserAccountRepository;
import com.polyp.polypweb.view.AdminDashboardView;
import com.polyp.polypweb.view.AiHealthView;
import com.polyp.polypweb.view.DailyUsageView;
import com.polyp.polypweb.view.ModelHealthView;
import com.polyp.polypweb.view.RecentActivityView;
import com.polyp.polypweb.view.RecentUserView;
import com.polyp.polypweb.view.UserDashboardView;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class DashboardService {

    private static final Logger LOGGER = LoggerFactory.getLogger(DashboardService.class);
    private static final String BASELINE_MODEL = "YOLO26s-seg";
    private static final String VMAMBA_MODEL = "YOLO26s-TSVM-FP32-seg";
    private static final int CHART_DAYS = 7;
    private static final int RECENT_LIMIT = 10;
    private static final ZoneId DASHBOARD_ZONE = ZoneId.of("Asia/Ho_Chi_Minh");
    private static final DateTimeFormatter DAY_LABEL = DateTimeFormatter.ofPattern("dd/MM");

    private final DashboardStatisticsRepository statisticsRepository;
    private final DiagnosisHistoryRepository historyRepository;
    private final UserAccountRepository userAccountRepository;
    private final AiInferenceClient aiInferenceClient;

    public DashboardService(
            DashboardStatisticsRepository statisticsRepository,
            DiagnosisHistoryRepository historyRepository,
            UserAccountRepository userAccountRepository,
            AiInferenceClient aiInferenceClient) {
        this.statisticsRepository = statisticsRepository;
        this.historyRepository = historyRepository;
        this.userAccountRepository = userAccountRepository;
        this.aiInferenceClient = aiInferenceClient;
    }

    public UserDashboardView userDashboard(String userId, String fullName) {
        DashboardStatisticsSnapshot statistics = safeStatistics(userId);
        List<DiagnosisHistory> recent = safeUserRecent(userId);
        return new UserDashboardView(
                fullName,
                statistics.getSingleAnalysis(),
                statistics.getComparisonSessions(),
                statistics.getTotalInference(),
                statistics.getDetected(),
                statistics.getNotDetected(),
                statistics.getBaselineUsage(),
                statistics.getVmambaUsage(),
                statistics.getTotalMasks(),
                statistics.getAverageProcessingTimeMs(),
                statistics.getAverageDetectedConfidence(),
                percentage(statistics.getDetected(), statistics.getTotalInference()),
                mostUsedModel(statistics),
                dailyUsage(statistics),
                recentActivities(recent, Map.of(), true)
        );
    }

    public AdminDashboardView adminDashboard() {
        DashboardStatisticsSnapshot statistics = safeStatistics(null);
        List<DiagnosisHistory> recent = safeSystemRecent();
        Map<String, String> userDisplays = userDisplays(recent);
        List<RecentUserView> recentUsers = safeRecentUsers();

        return new AdminDashboardView(
                userAccountRepository.count(),
                userAccountRepository.countByEnabledTrue(),
                userAccountRepository.countByEnabledFalse(),
                userAccountRepository.countByRole(UserRole.USER),
                userAccountRepository.countByRole(UserRole.ADMIN),
                statistics.getTotalInference(),
                statistics.getSingleAnalysis(),
                statistics.getComparisonSessions(),
                statistics.getBaselineUsage(),
                statistics.getVmambaUsage(),
                statistics.getDetected(),
                statistics.getNotDetected(),
                statistics.getTotalMasks(),
                statistics.getActivityLast24Hours(),
                statistics.getAverageProcessingTimeMs(),
                dailyUsage(statistics),
                recentActivities(recent, userDisplays, false),
                recentUsers,
                safeHealth()
        );
    }

    private DashboardStatisticsSnapshot safeStatistics(String userId) {
        try {
            return statisticsRepository.aggregate(userId, CHART_DAYS);
        } catch (RuntimeException exception) {
            LOGGER.error("Không thể tổng hợp dữ liệu dashboard từ MongoDB.", exception);
            return DashboardStatisticsSnapshot.empty();
        }
    }

    private List<DiagnosisHistory> safeUserRecent(String userId) {
        try {
            return historyRepository.findTop20ByUserIdOrderByCreatedAtDesc(userId);
        } catch (RuntimeException exception) {
            LOGGER.error("Không thể tải hoạt động dashboard của user {}.", userId, exception);
            return List.of();
        }
    }

    private List<DiagnosisHistory> safeSystemRecent() {
        try {
            return historyRepository.findTop20ByOrderByCreatedAtDesc();
        } catch (RuntimeException exception) {
            LOGGER.error("Không thể tải hoạt động gần đây toàn hệ thống.", exception);
            return List.of();
        }
    }

    private List<RecentUserView> safeRecentUsers() {
        try {
            return userAccountRepository
                    .findTop5ByCreatedAtAfterOrderByCreatedAtDesc(
                            LocalDateTime.now().minusDays(7)
                    )
                    .stream()
                    .map(account -> new RecentUserView(
                            account.getFullName(),
                            account.getEmail(),
                            account.getRole(),
                            account.isEnabled(),
                            account.getCreatedAt()
                    ))
                    .toList();
        } catch (RuntimeException exception) {
            LOGGER.error("Không thể tải danh sách user mới.", exception);
            return List.of();
        }
    }

    private AiHealthView safeHealth() {
        try {
            return aiInferenceClient.dashboardHealth();
        } catch (AiServiceException exception) {
            LOGGER.warn("FastAPI health không khả dụng cho admin dashboard: {}", exception.getMessage());
            return new AiHealthView(
                    false,
                    "Không khả dụng",
                    "Không xác định",
                    List.of(
                            new ModelHealthView(
                                    BASELINE_MODEL,
                                    "Baseline",
                                    "Không khả dụng",
                                    false
                            ),
                            new ModelHealthView(
                                    VMAMBA_MODEL,
                                    "VMamba",
                                    "Không khả dụng",
                                    false
                            )
                    )
            );
        }
    }

    private List<DailyUsageView> dailyUsage(DashboardStatisticsSnapshot statistics) {
        LocalDate firstDay = LocalDate.now(DASHBOARD_ZONE).minusDays(CHART_DAYS - 1L);
        long maximum = statistics.getDailyUsage()
                .values()
                .stream()
                .mapToLong(Long::longValue)
                .max()
                .orElse(0);
        List<DailyUsageView> days = new ArrayList<>();
        for (int index = 0; index < CHART_DAYS; index++) {
            LocalDate date = firstDay.plusDays(index);
            long count = statistics.getDailyUsage().getOrDefault(date, 0L);
            double barPercentage = maximum == 0 ? 0 : count * 100.0 / maximum;
            days.add(new DailyUsageView(
                    date,
                    DAY_LABEL.format(date),
                    count,
                    barPercentage
            ));
        }
        return days;
    }

    private List<RecentActivityView> recentActivities(
            List<DiagnosisHistory> histories,
            Map<String, String> userDisplays,
            boolean includeThumbnail) {
        Map<String, List<DiagnosisHistory>> grouped = new LinkedHashMap<>();
        for (DiagnosisHistory history : histories) {
            String key = history.isComparisonResult()
                    && history.getComparisonGroupId() != null
                    && !history.getComparisonGroupId().isBlank()
                    ? "comparison:" + history.getComparisonGroupId()
                    : "diagnosis:" + history.getId();
            grouped.computeIfAbsent(key, ignored -> new ArrayList<>()).add(history);
        }

        return grouped.values()
                .stream()
                .limit(RECENT_LIMIT)
                .map(group -> recentActivity(group, userDisplays, includeThumbnail))
                .toList();
    }

    private RecentActivityView recentActivity(
            List<DiagnosisHistory> group,
            Map<String, String> userDisplays,
            boolean includeThumbnail) {
        DiagnosisHistory first = group.get(0);
        boolean comparison = first.isComparisonResult()
                && first.getComparisonGroupId() != null
                && !first.getComparisonGroupId().isBlank();
        Set<String> models = new LinkedHashSet<>();
        group.stream()
                .map(DiagnosisHistory::getModelType)
                .filter(model -> model != null && !model.isBlank())
                .forEach(models::add);
        boolean detected = group.stream().anyMatch(DiagnosisHistory::isDetected);
        double confidence = group.stream()
                .filter(DiagnosisHistory::isDetected)
                .mapToDouble(DiagnosisHistory::getConfidence)
                .max()
                .orElse(0);
        double processingTime = group.stream()
                .mapToDouble(DiagnosisHistory::getProcessingTimeMs)
                .filter(value -> value >= 0)
                .sum();
        int maskCount = group.stream()
                .mapToInt(DiagnosisHistory::getMaskCount)
                .filter(value -> value >= 0)
                .sum();
        LocalDateTime createdAt = group.stream()
                .map(DiagnosisHistory::getCreatedAt)
                .filter(value -> value != null)
                .max(Comparator.naturalOrder())
                .orElse(null);
        String detailUrl = comparison
                ? "/comparisons/" + first.getComparisonGroupId()
                : "/diagnoses/" + first.getId();
        String thumbnailUrl = includeThumbnail
                ? "/diagnoses/" + first.getId() + "/original-image"
                : null;

        return new RecentActivityView(
                first.getId(),
                comparison ? first.getComparisonGroupId() : null,
                first.getFileName(),
                models.isEmpty() ? "Không xác định" : String.join(" + ", models),
                familyLabel(models),
                comparison ? "Phiên so sánh" : "Phân tích đơn",
                detected,
                confidence,
                processingTime,
                createdAt,
                detailUrl,
                thumbnailUrl,
                userDisplays.getOrDefault(first.getUserId(), "Tài khoản không xác định"),
                group.size(),
                maskCount
        );
    }

    private Map<String, String> userDisplays(List<DiagnosisHistory> histories) {
        Set<String> userIds = new LinkedHashSet<>();
        histories.stream()
                .map(DiagnosisHistory::getUserId)
                .filter(value -> value != null && !value.isBlank())
                .forEach(userIds::add);
        if (userIds.isEmpty()) {
            return Map.of();
        }
        try {
            Map<String, String> displays = new LinkedHashMap<>();
            for (UserAccount account : userAccountRepository.findAllById(userIds)) {
                String display = account.getFullName() == null || account.getFullName().isBlank()
                        ? account.getEmail()
                        : account.getFullName();
                displays.put(account.getId(), display);
            }
            return displays;
        } catch (RuntimeException exception) {
            LOGGER.error("Không thể tải thông tin tài khoản cho hoạt động gần đây.", exception);
            return Map.of();
        }
    }

    private double percentage(long part, long total) {
        return total == 0 ? 0 : part * 100.0 / total;
    }

    private String mostUsedModel(DashboardStatisticsSnapshot statistics) {
        if (statistics.getBaselineUsage() == 0 && statistics.getVmambaUsage() == 0) {
            return "Chưa có dữ liệu";
        }
        if (statistics.getBaselineUsage() == statistics.getVmambaUsage()) {
            return "Hai mô hình dùng ngang nhau";
        }
        return statistics.getBaselineUsage() > statistics.getVmambaUsage()
                ? BASELINE_MODEL
                : VMAMBA_MODEL;
    }

    private String familyLabel(Set<String> models) {
        boolean baseline = models.contains(BASELINE_MODEL);
        boolean vmamba = models.contains(VMAMBA_MODEL);
        if (baseline && vmamba) {
            return "Baseline + VMamba";
        }
        if (vmamba) {
            return "VMamba";
        }
        if (baseline) {
            return "Baseline";
        }
        return "Không xác định";
    }
}
