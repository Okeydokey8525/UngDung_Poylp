package com.polyp.polypweb.view;

import java.util.List;

public class AdminDashboardView {

    private final long totalUsers;
    private final long enabledUsers;
    private final long disabledUsers;
    private final long userRoleCount;
    private final long adminRoleCount;
    private final long totalHistory;
    private final long singleAnalysis;
    private final long comparisonSessions;
    private final long baselineUsage;
    private final long vmambaUsage;
    private final long detected;
    private final long notDetected;
    private final long totalMasks;
    private final long activityLast24Hours;
    private final double averageProcessingTimeMs;
    private final List<DailyUsageView> dailyUsage;
    private final List<RecentActivityView> recentActivities;
    private final List<RecentUserView> recentUsers;
    private final AiHealthView aiHealth;

    public AdminDashboardView(
            long totalUsers,
            long enabledUsers,
            long disabledUsers,
            long userRoleCount,
            long adminRoleCount,
            long totalHistory,
            long singleAnalysis,
            long comparisonSessions,
            long baselineUsage,
            long vmambaUsage,
            long detected,
            long notDetected,
            long totalMasks,
            long activityLast24Hours,
            double averageProcessingTimeMs,
            List<DailyUsageView> dailyUsage,
            List<RecentActivityView> recentActivities,
            List<RecentUserView> recentUsers,
            AiHealthView aiHealth) {
        this.totalUsers = totalUsers;
        this.enabledUsers = enabledUsers;
        this.disabledUsers = disabledUsers;
        this.userRoleCount = userRoleCount;
        this.adminRoleCount = adminRoleCount;
        this.totalHistory = totalHistory;
        this.singleAnalysis = singleAnalysis;
        this.comparisonSessions = comparisonSessions;
        this.baselineUsage = baselineUsage;
        this.vmambaUsage = vmambaUsage;
        this.detected = detected;
        this.notDetected = notDetected;
        this.totalMasks = totalMasks;
        this.activityLast24Hours = activityLast24Hours;
        this.averageProcessingTimeMs = averageProcessingTimeMs;
        this.dailyUsage = List.copyOf(dailyUsage);
        this.recentActivities = List.copyOf(recentActivities);
        this.recentUsers = List.copyOf(recentUsers);
        this.aiHealth = aiHealth;
    }

    public long getTotalUsers() {
        return totalUsers;
    }

    public long getEnabledUsers() {
        return enabledUsers;
    }

    public long getDisabledUsers() {
        return disabledUsers;
    }

    public long getUserRoleCount() {
        return userRoleCount;
    }

    public long getAdminRoleCount() {
        return adminRoleCount;
    }

    public long getTotalHistory() {
        return totalHistory;
    }

    public long getSingleAnalysis() {
        return singleAnalysis;
    }

    public long getComparisonSessions() {
        return comparisonSessions;
    }

    public long getBaselineUsage() {
        return baselineUsage;
    }

    public long getVmambaUsage() {
        return vmambaUsage;
    }

    public long getDetected() {
        return detected;
    }

    public long getNotDetected() {
        return notDetected;
    }

    public long getTotalMasks() {
        return totalMasks;
    }

    public long getActivityLast24Hours() {
        return activityLast24Hours;
    }

    public double getAverageProcessingTimeMs() {
        return averageProcessingTimeMs;
    }

    public List<DailyUsageView> getDailyUsage() {
        return dailyUsage;
    }

    public List<RecentActivityView> getRecentActivities() {
        return recentActivities;
    }

    public List<RecentUserView> getRecentUsers() {
        return recentUsers;
    }

    public AiHealthView getAiHealth() {
        return aiHealth;
    }

    public double getBaselineRate() {
        return percentage(baselineUsage, totalHistory);
    }

    public double getVmambaRate() {
        return percentage(vmambaUsage, totalHistory);
    }

    public double getDetectedRate() {
        return percentage(detected, totalHistory);
    }

    public double getNotDetectedRate() {
        return percentage(notDetected, totalHistory);
    }

    private double percentage(long value, long total) {
        return total == 0 ? 0 : value * 100.0 / total;
    }
}
