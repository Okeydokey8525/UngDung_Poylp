package com.polyp.polypweb.api.dto;

import com.polyp.polypweb.view.ComparisonResultView;

import java.time.LocalDateTime;

public record ApiComparisonHistoryItemResponse(
        String comparisonGroupId,
        String fileName,
        LocalDateTime createdAt,
        String originalImageUrl,
        ApiComparisonHistoryModelResponse baseline,
        ApiComparisonHistoryModelResponse vmamba,
        double totalProcessingTimeMs
) {

    public static ApiComparisonHistoryItemResponse from(ComparisonResultView comparison) {
        ApiComparisonHistoryModelResponse baseline =
                ApiComparisonHistoryModelResponse.from(comparison.getBaselineResult());
        ApiComparisonHistoryModelResponse vmamba =
                ApiComparisonHistoryModelResponse.from(comparison.getVmambaResult());
        return new ApiComparisonHistoryItemResponse(
                safe(comparison.getComparisonGroupId()),
                safe(comparison.getOriginalFileName()),
                comparison.getCreatedAt(),
                "/api/v1/diagnoses/" + baseline.id() + "/images/original",
                baseline,
                vmamba,
                baseline.processingTimeMs() + vmamba.processingTimeMs()
        );
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}
