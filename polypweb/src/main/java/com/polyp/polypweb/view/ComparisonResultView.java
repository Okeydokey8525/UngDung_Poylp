package com.polyp.polypweb.view;

import java.time.LocalDateTime;

public class ComparisonResultView {

    private final String comparisonGroupId;
    private final DiagnosisResultView baselineResult;
    private final DiagnosisResultView vmambaResult;
    private final String originalImageUrl;
    private final String originalFileName;
    private final LocalDateTime createdAt;

    public ComparisonResultView(
            String comparisonGroupId,
            DiagnosisResultView baselineResult,
            DiagnosisResultView vmambaResult,
            String originalImageUrl,
            String originalFileName,
            LocalDateTime createdAt) {
        this.comparisonGroupId = comparisonGroupId;
        this.baselineResult = baselineResult;
        this.vmambaResult = vmambaResult;
        this.originalImageUrl = originalImageUrl;
        this.originalFileName = originalFileName;
        this.createdAt = createdAt;
    }

    public String getComparisonGroupId() {
        return comparisonGroupId;
    }

    public String getShortGroupId() {
        return comparisonGroupId == null || comparisonGroupId.length() < 8
                ? comparisonGroupId
                : comparisonGroupId.substring(0, 8);
    }

    public DiagnosisResultView getBaselineResult() {
        return baselineResult;
    }

    public DiagnosisResultView getVmambaResult() {
        return vmambaResult;
    }

    public String getOriginalImageUrl() {
        return originalImageUrl;
    }

    public String getOriginalFileName() {
        return originalFileName;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public double getTotalProcessingTimeMs() {
        return baselineResult.getProcessingTimeMs() + vmambaResult.getProcessingTimeMs();
    }
}
