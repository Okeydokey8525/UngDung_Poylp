package com.polyp.polypweb.api.dto;

import java.time.LocalDateTime;

public record ApiComparisonMetadataResponse(
        String comparisonGroupId,
        String fileName,
        LocalDateTime createdAt,
        double totalProcessingTimeMs,
        ApiComparisonModelResultResponse baseline,
        ApiComparisonModelResultResponse vmamba
) {

    public static ApiComparisonMetadataResponse from(ApiComparisonResponse comparison) {
        return new ApiComparisonMetadataResponse(
                comparison.comparisonGroupId(),
                comparison.fileName(),
                comparison.createdAt(),
                comparison.totalProcessingTimeMs(),
                comparison.baseline(),
                comparison.vmamba()
        );
    }
}
