package com.polyp.polypweb.view.export;

import java.time.LocalDateTime;

public record ModelMetadataExport(
        String id,
        String modelType,
        String modelCategory,
        boolean detected,
        String label,
        double confidence,
        int maskCount,
        double processingTimeMs,
        LocalDateTime createdAt) {
}
