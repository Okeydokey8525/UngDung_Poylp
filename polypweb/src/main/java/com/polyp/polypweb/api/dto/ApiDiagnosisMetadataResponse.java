package com.polyp.polypweb.api.dto;

import java.time.LocalDateTime;

public record ApiDiagnosisMetadataResponse(
        String id,
        String fileName,
        String modelType,
        String modelCategory,
        boolean detected,
        String label,
        double confidence,
        int maskCount,
        double processingTimeMs,
        LocalDateTime createdAt
) {

    public static ApiDiagnosisMetadataResponse from(ApiDiagnosisResponse diagnosis) {
        return new ApiDiagnosisMetadataResponse(
                diagnosis.id(),
                diagnosis.fileName(),
                diagnosis.modelType(),
                diagnosis.modelCategory(),
                diagnosis.detected(),
                diagnosis.label(),
                diagnosis.confidence(),
                diagnosis.maskCount(),
                diagnosis.processingTimeMs(),
                diagnosis.createdAt()
        );
    }
}
