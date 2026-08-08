package com.polyp.polypweb.api.dto;

import java.time.LocalDateTime;

public record ApiRecentActivityResponse(
        String id,
        String type,
        String fileName,
        String modelType,
        boolean detected,
        double confidence,
        int maskCount,
        double processingTimeMs,
        LocalDateTime createdAt,
        String comparisonGroupId,
        String originalImageUrl
) {
}
