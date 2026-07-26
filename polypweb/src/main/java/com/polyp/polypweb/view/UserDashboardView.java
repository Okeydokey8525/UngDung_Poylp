package com.polyp.polypweb.view;

import java.util.List;

public class UserDashboardView {

    private final String fullName;
    private final long singleAnalysis;
    private final long comparisonSessions;
    private final long totalInference;
    private final long detected;
    private final long notDetected;
    private final long baselineUsage;
    private final long vmambaUsage;
    private final long totalMasks;
    private final double averageProcessingTimeMs;
    private final double averageDetectedConfidence;
    private final double detectedRate;
    private final String mostUsedModel;
    private final List<DailyUsageView> dailyUsage;
    private final List<RecentActivityView> recentActivities;

    public UserDashboardView(
            String fullName,
            long singleAnalysis,
            long comparisonSessions,
            long totalInference,
            long detected,
            long notDetected,
            long baselineUsage,
            long vmambaUsage,
            long totalMasks,
            double averageProcessingTimeMs,
            double averageDetectedConfidence,
            double detectedRate,
            String mostUsedModel,
            List<DailyUsageView> dailyUsage,
            List<RecentActivityView> recentActivities) {
        this.fullName = fullName;
        this.singleAnalysis = singleAnalysis;
        this.comparisonSessions = comparisonSessions;
        this.totalInference = totalInference;
        this.detected = detected;
        this.notDetected = notDetected;
        this.baselineUsage = baselineUsage;
        this.vmambaUsage = vmambaUsage;
        this.totalMasks = totalMasks;
        this.averageProcessingTimeMs = averageProcessingTimeMs;
        this.averageDetectedConfidence = averageDetectedConfidence;
        this.detectedRate = detectedRate;
        this.mostUsedModel = mostUsedModel;
        this.dailyUsage = List.copyOf(dailyUsage);
        this.recentActivities = List.copyOf(recentActivities);
    }

    public String getFullName() {
        return fullName;
    }

    public long getSingleAnalysis() {
        return singleAnalysis;
    }

    public long getComparisonSessions() {
        return comparisonSessions;
    }

    public long getTotalInference() {
        return totalInference;
    }

    public long getDetected() {
        return detected;
    }

    public long getNotDetected() {
        return notDetected;
    }

    public long getBaselineUsage() {
        return baselineUsage;
    }

    public long getVmambaUsage() {
        return vmambaUsage;
    }

    public long getTotalMasks() {
        return totalMasks;
    }

    public double getAverageProcessingTimeMs() {
        return averageProcessingTimeMs;
    }

    public double getAverageDetectedConfidence() {
        return averageDetectedConfidence;
    }

    public double getDetectedRate() {
        return detectedRate;
    }

    public String getMostUsedModel() {
        return mostUsedModel;
    }

    public double getBaselineRate() {
        return percentage(baselineUsage, totalInference);
    }

    public double getVmambaRate() {
        return percentage(vmambaUsage, totalInference);
    }

    public List<DailyUsageView> getDailyUsage() {
        return dailyUsage;
    }

    public List<RecentActivityView> getRecentActivities() {
        return recentActivities;
    }

    public boolean isEmpty() {
        return totalInference == 0;
    }

    private double percentage(long value, long total) {
        return total == 0 ? 0 : value * 100.0 / total;
    }
}
