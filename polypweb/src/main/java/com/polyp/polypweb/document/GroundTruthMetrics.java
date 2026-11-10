package com.polyp.polypweb.document;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/**
 * Pixel metrics of one prediction against a user-supplied ground-truth mask (computed by FastAPI with the
 * thesis protocol). Embedded in {@link DiagnosisHistory}; null when no mask was uploaded. Ratios are null
 * when undefined, e.g. on a background image with no predicted pixel.
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class GroundTruthMetrics {

    private Double dice;
    private Double iou;
    private Double precision;
    private Double recall;
    private long truePositivePixels;
    private long falsePositivePixels;
    private long falseNegativePixels;
    private long groundTruthPixels;
    private long predictedPixels;
    private long imagePixels;
    private boolean backgroundImage;

    public GroundTruthMetrics() {
    }

    public Double getDice() {
        return dice;
    }

    public void setDice(Double dice) {
        this.dice = dice;
    }

    public Double getIou() {
        return iou;
    }

    public void setIou(Double iou) {
        this.iou = iou;
    }

    public Double getPrecision() {
        return precision;
    }

    public void setPrecision(Double precision) {
        this.precision = precision;
    }

    public Double getRecall() {
        return recall;
    }

    public void setRecall(Double recall) {
        this.recall = recall;
    }

    public long getTruePositivePixels() {
        return truePositivePixels;
    }

    public void setTruePositivePixels(long truePositivePixels) {
        this.truePositivePixels = truePositivePixels;
    }

    public long getFalsePositivePixels() {
        return falsePositivePixels;
    }

    public void setFalsePositivePixels(long falsePositivePixels) {
        this.falsePositivePixels = falsePositivePixels;
    }

    public long getFalseNegativePixels() {
        return falseNegativePixels;
    }

    public void setFalseNegativePixels(long falseNegativePixels) {
        this.falseNegativePixels = falseNegativePixels;
    }

    public long getGroundTruthPixels() {
        return groundTruthPixels;
    }

    public void setGroundTruthPixels(long groundTruthPixels) {
        this.groundTruthPixels = groundTruthPixels;
    }

    public long getPredictedPixels() {
        return predictedPixels;
    }

    public void setPredictedPixels(long predictedPixels) {
        this.predictedPixels = predictedPixels;
    }

    public long getImagePixels() {
        return imagePixels;
    }

    public void setImagePixels(long imagePixels) {
        this.imagePixels = imagePixels;
    }

    public boolean isBackgroundImage() {
        return backgroundImage;
    }

    public void setBackgroundImage(boolean backgroundImage) {
        this.backgroundImage = backgroundImage;
    }
}
