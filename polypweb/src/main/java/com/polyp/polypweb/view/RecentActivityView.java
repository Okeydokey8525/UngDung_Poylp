package com.polyp.polypweb.view;

import java.time.LocalDateTime;

public class RecentActivityView {

    private final String id;
    private final String comparisonGroupId;
    private final String fileName;
    private final String modelLabel;
    private final String familyLabel;
    private final String activityType;
    private final boolean detected;
    private final double confidence;
    private final double processingTimeMs;
    private final LocalDateTime createdAt;
    private final String detailUrl;
    private final String thumbnailUrl;
    private final String userDisplay;
    private final int inferenceCount;
    private final int maskCount;

    public RecentActivityView(
            String id,
            String comparisonGroupId,
            String fileName,
            String modelLabel,
            String familyLabel,
            String activityType,
            boolean detected,
            double confidence,
            double processingTimeMs,
            LocalDateTime createdAt,
            String detailUrl,
            String thumbnailUrl,
            String userDisplay,
            int inferenceCount,
            int maskCount) {
        this.id = id;
        this.comparisonGroupId = comparisonGroupId;
        this.fileName = fileName;
        this.modelLabel = modelLabel;
        this.familyLabel = familyLabel;
        this.activityType = activityType;
        this.detected = detected;
        this.confidence = confidence;
        this.processingTimeMs = processingTimeMs;
        this.createdAt = createdAt;
        this.detailUrl = detailUrl;
        this.thumbnailUrl = thumbnailUrl;
        this.userDisplay = userDisplay;
        this.inferenceCount = inferenceCount;
        this.maskCount = maskCount;
    }

    public String getId() {
        return id;
    }

    public String getComparisonGroupId() {
        return comparisonGroupId;
    }

    public String getFileName() {
        return fileName;
    }

    public String getModelLabel() {
        return modelLabel;
    }

    public String getFamilyLabel() {
        return familyLabel;
    }

    public String getActivityType() {
        return activityType;
    }

    public boolean isDetected() {
        return detected;
    }

    public double getConfidence() {
        return confidence;
    }

    public double getProcessingTimeMs() {
        return processingTimeMs;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public String getDetailUrl() {
        return detailUrl;
    }

    public String getThumbnailUrl() {
        return thumbnailUrl;
    }

    public String getUserDisplay() {
        return userDisplay;
    }

    public int getInferenceCount() {
        return inferenceCount;
    }

    public int getMaskCount() {
        return maskCount;
    }
}
