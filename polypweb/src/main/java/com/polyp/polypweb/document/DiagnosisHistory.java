package com.polyp.polypweb.document;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.LocalDateTime;

@Document(collection = "diagnosis_history")
public class DiagnosisHistory {

    @Id
    private String id;

    private String userId;
    private String fileName;
    private String modelType;
    private boolean detected;
    private String label;
    private double confidence;
    private double processingTimeMs;
    private int maskCount;
    private Integer imageWidth;
    private Integer imageHeight;
    private String originalImageUrl;
    private String resultImageUrl;
    private LocalDateTime createdAt;
    private String comparisonGroupId;
    private boolean comparisonResult;

    public DiagnosisHistory() {
    }

    public DiagnosisHistory(
            String userId,
            String fileName,
            String modelType,
            boolean detected,
            String label,
            double confidence,
            double processingTimeMs,
            int maskCount,
            String originalImageUrl,
            String resultImageUrl,
            LocalDateTime createdAt,
            String comparisonGroupId,
            boolean comparisonResult) {
        this.userId = userId;
        this.fileName = fileName;
        this.modelType = modelType;
        this.detected = detected;
        this.label = label;
        this.confidence = confidence;
        this.processingTimeMs = processingTimeMs;
        this.maskCount = maskCount;
        this.originalImageUrl = originalImageUrl;
        this.resultImageUrl = resultImageUrl;
        this.createdAt = createdAt;
        this.comparisonGroupId = comparisonGroupId;
        this.comparisonResult = comparisonResult;
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getUserId() {
        return userId;
    }

    public void setUserId(String userId) {
        this.userId = userId;
    }

    public String getFileName() {
        return fileName;
    }

    public void setFileName(String fileName) {
        this.fileName = fileName;
    }

    public String getModelType() {
        return modelType;
    }

    public void setModelType(String modelType) {
        this.modelType = modelType;
    }

    public boolean isDetected() {
        return detected;
    }

    public void setDetected(boolean detected) {
        this.detected = detected;
    }

    public String getLabel() {
        return label;
    }

    public void setLabel(String label) {
        this.label = label;
    }

    public double getConfidence() {
        return confidence;
    }

    public void setConfidence(double confidence) {
        this.confidence = confidence;
    }

    public double getProcessingTimeMs() {
        return processingTimeMs;
    }

    public void setProcessingTimeMs(double processingTimeMs) {
        this.processingTimeMs = processingTimeMs;
    }

    public int getMaskCount() {
        return maskCount;
    }

    public void setMaskCount(int maskCount) {
        this.maskCount = maskCount;
    }

    public Integer getImageWidth() {
        return imageWidth;
    }

    public void setImageWidth(Integer imageWidth) {
        this.imageWidth = imageWidth;
    }

    public Integer getImageHeight() {
        return imageHeight;
    }

    public void setImageHeight(Integer imageHeight) {
        this.imageHeight = imageHeight;
    }

    public String getOriginalImageUrl() {
        return originalImageUrl;
    }

    public void setOriginalImageUrl(String originalImageUrl) {
        this.originalImageUrl = originalImageUrl;
    }

    public String getResultImageUrl() {
        return resultImageUrl;
    }

    public void setResultImageUrl(String resultImageUrl) {
        this.resultImageUrl = resultImageUrl;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public String getComparisonGroupId() {
        return comparisonGroupId;
    }

    public void setComparisonGroupId(String comparisonGroupId) {
        this.comparisonGroupId = comparisonGroupId;
    }

    public boolean isComparisonResult() {
        return comparisonResult;
    }

    public void setComparisonResult(boolean comparisonResult) {
        this.comparisonResult = comparisonResult;
    }
}
