package com.polyp.polypweb.api.dto;

import com.polyp.polypweb.view.ComparisonResultView;

import java.time.LocalDateTime;

public record ApiComparisonResponse(
        String comparisonGroupId,
        String fileName,
        LocalDateTime createdAt,
        String originalImageUrl,
        ApiComparisonModelResultResponse baseline,
        ApiComparisonModelResultResponse vmamba,
        double totalProcessingTimeMs,
        String metadataUrl
) {

    public static ApiComparisonResponse from(ComparisonResultView comparison) {
        ApiComparisonModelResultResponse baseline =
                ApiComparisonModelResultResponse.from(comparison.getBaselineResult());
        ApiComparisonModelResultResponse vmamba =
                ApiComparisonModelResultResponse.from(comparison.getVmambaResult());
        String groupId = safe(comparison.getComparisonGroupId());
        return new ApiComparisonResponse(
                groupId,
                safe(comparison.getOriginalFileName()),
                comparison.getCreatedAt(),
                "/api/v1/diagnoses/" + baseline.id() + "/images/original",
                baseline,
                vmamba,
                nonNegative(baseline.processingTimeMs() + vmamba.processingTimeMs()),
                "/api/v1/comparisons/" + groupId + "/metadata"
        );
    }

    private static double nonNegative(double value) {
        return Double.isFinite(value) ? Math.max(0, value) : 0;
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}
