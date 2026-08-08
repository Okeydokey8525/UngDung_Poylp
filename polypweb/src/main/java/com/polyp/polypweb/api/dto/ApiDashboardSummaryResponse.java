package com.polyp.polypweb.api.dto;

public record ApiDashboardSummaryResponse(
        long singleAnalysisCount,
        long comparisonSessionCount,
        long totalInferenceCount,
        long detectedCount,
        long notDetectedCount,
        long baselineCount,
        long vmambaCount,
        double averageProcessingTimeMs,
        double averageDetectedConfidence,
        long totalMaskCount,
        double detectedRate,
        String mostUsedModel
) {
}
