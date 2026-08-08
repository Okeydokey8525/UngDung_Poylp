package com.polyp.polypweb.api.dto;

import com.polyp.polypweb.service.DiagnosisModel;
import com.polyp.polypweb.view.DiagnosisResultView;

public record ApiComparisonModelResultResponse(
        String id,
        String modelType,
        String modelCategory,
        boolean detected,
        String label,
        double confidence,
        int maskCount,
        double processingTimeMs,
        String resultImageUrl
) {

    public static ApiComparisonModelResultResponse from(DiagnosisResultView result) {
        String id = safe(result.getId());
        String modelType = safe(result.getModelType());
        return new ApiComparisonModelResultResponse(
                id,
                modelType,
                DiagnosisModel.fromModelType(modelType)
                        .map(DiagnosisModel::getCategory)
                        .orElse("UNKNOWN"),
                result.isDetected(),
                blankToNull(result.getLabel()),
                result.isDetected() ? confidenceRatio(result.getConfidence()) : 0,
                Math.max(0, result.getMaskCount()),
                nonNegative(result.getProcessingTimeMs()),
                "/api/v1/diagnoses/" + id + "/images/result"
        );
    }

    private static double confidenceRatio(double value) {
        double ratio = value > 1 ? value / 100.0 : value;
        return Double.isFinite(ratio) ? Math.max(0, Math.min(1, ratio)) : 0;
    }

    private static double nonNegative(double value) {
        return Double.isFinite(value) ? Math.max(0, value) : 0;
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }
}
