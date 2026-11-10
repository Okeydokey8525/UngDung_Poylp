package com.polyp.polypweb.view;

import com.polyp.polypweb.document.GroundTruthMetrics;

public class AiPredictionResponse {

    private boolean success;
    private boolean detected;
    private String label;
    private double confidence;
    private double processingTimeMs;
    private int maskCount;
    private String modelType;
    private String originalFileName;
    private String resultImageBase64;
    private String message;
    private Double aiRoundTripMs;
    private GroundTruthMetrics groundTruthMetrics;

    public AiPredictionResponse() {
    }

    /** Spring-measured round trip of the FastAPI call (upload, decode, inference, overlay, response); null for older records. */
    public Double getAiRoundTripMs() {
        return aiRoundTripMs;
    }

    public void setAiRoundTripMs(Double aiRoundTripMs) {
        this.aiRoundTripMs = aiRoundTripMs;
    }

    /** Pixel metrics against an uploaded ground-truth mask; null when no mask was uploaded. */
    public GroundTruthMetrics getGroundTruthMetrics() {
        return groundTruthMetrics;
    }

    public void setGroundTruthMetrics(GroundTruthMetrics groundTruthMetrics) {
        this.groundTruthMetrics = groundTruthMetrics;
    }

    public boolean isSuccess() {
        return success;
    }

    public void setSuccess(boolean success) {
        this.success = success;
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

    public String getModelType() {
        return modelType;
    }

    public void setModelType(String modelType) {
        this.modelType = modelType;
    }

    public String getOriginalFileName() {
        return originalFileName;
    }

    public void setOriginalFileName(String originalFileName) {
        this.originalFileName = originalFileName;
    }

    public String getResultImageBase64() {
        return resultImageBase64;
    }

    public void setResultImageBase64(String resultImageBase64) {
        this.resultImageBase64 = resultImageBase64;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }
}
