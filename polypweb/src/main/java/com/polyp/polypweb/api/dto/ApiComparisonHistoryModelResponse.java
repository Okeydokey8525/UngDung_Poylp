package com.polyp.polypweb.api.dto;

import com.polyp.polypweb.view.DiagnosisResultView;

public record ApiComparisonHistoryModelResponse(
        String id,
        boolean detected,
        double confidence,
        int maskCount,
        double processingTimeMs,
        String resultImageUrl
) {

    public static ApiComparisonHistoryModelResponse from(DiagnosisResultView result) {
        String id = result.getId() == null ? "" : result.getId();
        double confidence = result.getConfidence() > 1
                ? result.getConfidence() / 100.0
                : result.getConfidence();
        confidence = Double.isFinite(confidence)
                ? Math.max(0, Math.min(1, confidence))
                : 0;
        double processing = Double.isFinite(result.getProcessingTimeMs())
                ? Math.max(0, result.getProcessingTimeMs())
                : 0;
        return new ApiComparisonHistoryModelResponse(
                id,
                result.isDetected(),
                result.isDetected() ? confidence : 0,
                Math.max(0, result.getMaskCount()),
                processing,
                "/api/v1/diagnoses/" + id + "/images/result"
        );
    }
}
