package com.polyp.polypweb.view.export;

import java.time.LocalDateTime;

public record DiagnosisMetadataExport(
        String id,
        String fileName,
        String modelType,
        String modelCategory,
        boolean detected,
        String label,
        double confidence,
        int maskCount,
        double processingTimeMs,
        String imageSize,
        LocalDateTime createdAt,
        boolean comparisonResult,
        String comparisonGroupId) {
}
