package com.polyp.polypweb.repository;

import com.polyp.polypweb.document.DiagnosisHistory;

import java.time.LocalDateTime;

public record ComparisonHistoryRecord(
        String comparisonGroupId,
        String fileName,
        LocalDateTime createdAt,
        double totalProcessingTimeMs,
        DiagnosisHistory baseline,
        DiagnosisHistory vmamba) {
}
