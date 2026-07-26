package com.polyp.polypweb.repository;

import java.time.LocalDate;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

public class DashboardStatisticsSnapshot {

    private final long totalInference;
    private final long singleAnalysis;
    private final long comparisonSessions;
    private final long detected;
    private final long notDetected;
    private final long baselineUsage;
    private final long vmambaUsage;
    private final long totalMasks;
    private final long activityLast24Hours;
    private final double averageProcessingTimeMs;
    private final double averageDetectedConfidence;
    private final Map<LocalDate, Long> dailyUsage;

    public DashboardStatisticsSnapshot(
            long totalInference,
            long singleAnalysis,
            long comparisonSessions,
            long detected,
            long notDetected,
            long baselineUsage,
            long vmambaUsage,
            long totalMasks,
            long activityLast24Hours,
            double averageProcessingTimeMs,
            double averageDetectedConfidence,
            Map<LocalDate, Long> dailyUsage) {
        this.totalInference = totalInference;
        this.singleAnalysis = singleAnalysis;
        this.comparisonSessions = comparisonSessions;
        this.detected = detected;
        this.notDetected = notDetected;
        this.baselineUsage = baselineUsage;
        this.vmambaUsage = vmambaUsage;
        this.totalMasks = totalMasks;
        this.activityLast24Hours = activityLast24Hours;
        this.averageProcessingTimeMs = averageProcessingTimeMs;
        this.averageDetectedConfidence = averageDetectedConfidence;
        this.dailyUsage = Collections.unmodifiableMap(new LinkedHashMap<>(dailyUsage));
    }

    public static DashboardStatisticsSnapshot empty() {
        return new DashboardStatisticsSnapshot(
                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Map.of()
        );
    }

    public long getTotalInference() {
        return totalInference;
    }

    public long getSingleAnalysis() {
        return singleAnalysis;
    }

    public long getComparisonSessions() {
        return comparisonSessions;
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

    public long getActivityLast24Hours() {
        return activityLast24Hours;
    }

    public double getAverageProcessingTimeMs() {
        return averageProcessingTimeMs;
    }

    public double getAverageDetectedConfidence() {
        return averageDetectedConfidence;
    }

    public Map<LocalDate, Long> getDailyUsage() {
        return dailyUsage;
    }
}
