package com.polyp.polypweb.view;

import java.time.LocalDateTime;

public class DiagnosisResultView {

    private final String id;
    private final String originalImageUrl;
    private final String resultImageUrl;
    private final String fileName;
    private final String modelType;
    private final boolean detected;
    private final String label;
    private final double confidence;
    private final double processingTimeMs;
    private final int maskCount;
    private final String imageSize;
    private final LocalDateTime createdAt;
    private final boolean historySaved;
    private final String comparisonGroupId;
    private final boolean comparisonResult;

    public DiagnosisResultView(
            String id,
            String originalImageUrl,
            String resultImageUrl,
            String fileName,
            String modelType,
            boolean detected,
            String label,
            double confidence,
            double processingTimeMs,
            String imageSize,
            LocalDateTime createdAt,
            boolean historySaved) {
        this(
                id,
                originalImageUrl,
                resultImageUrl,
                fileName,
                modelType,
                detected,
                label,
                confidence,
                processingTimeMs,
                0,
                imageSize,
                createdAt,
                historySaved,
                null,
                false
        );
    }

    public DiagnosisResultView(
            String id,
            String originalImageUrl,
            String resultImageUrl,
            String fileName,
            String modelType,
            boolean detected,
            String label,
            double confidence,
            double processingTimeMs,
            int maskCount,
            String imageSize,
            LocalDateTime createdAt,
            boolean historySaved,
            String comparisonGroupId,
            boolean comparisonResult) {
        this.id = id;
        this.originalImageUrl = originalImageUrl;
        this.resultImageUrl = resultImageUrl;
        this.fileName = fileName;
        this.modelType = modelType;
        this.detected = detected;
        this.label = label;
        this.confidence = confidence;
        this.processingTimeMs = processingTimeMs;
        this.maskCount = maskCount;
        this.imageSize = imageSize;
        this.createdAt = createdAt;
        this.historySaved = historySaved;
        this.comparisonGroupId = comparisonGroupId;
        this.comparisonResult = comparisonResult;
    }

    public String getId() {
        return id;
    }

    public String getOriginalImageUrl() {
        return originalImageUrl;
    }

    public String getResultImageUrl() {
        return resultImageUrl;
    }

    public String getFileName() {
        return fileName;
    }

    public String getModelType() {
        return modelType;
    }

    public boolean isDetected() {
        return detected;
    }

    public String getLabel() {
        return label;
    }

    public double getConfidence() {
        return confidence;
    }

    public double getProcessingTimeMs() {
        return processingTimeMs;
    }

    public int getMaskCount() {
        return maskCount;
    }

    public String getImageSize() {
        return imageSize;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public boolean isHistorySaved() {
        return historySaved;
    }

    public String getComparisonGroupId() {
        return comparisonGroupId;
    }

    public boolean isComparisonResult() {
        return comparisonResult;
    }
}
