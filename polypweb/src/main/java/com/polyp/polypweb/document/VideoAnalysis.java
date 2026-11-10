package com.polyp.polypweb.document;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/** Offline video analysis: sampled-frame segmentation, overlay video (MP4 or WebM) and detection timeline. */
@Document(collection = "video_analysis")
public class VideoAnalysis {

    @Id
    private String id;
    private String userId;
    private String fileName;
    private String modelType;
    private double sampleFps;
    private double requestedSampleFps;
    private boolean sampleRateReduced;
    /** Frame rate of the overlay video; 0 for results made before every source frame was kept. */
    private double outputFps;
    /** Overlay frames drawn with the mask of the latest analysed frame instead of their own. */
    private int framesHeld;
    private double sourceFps;
    private int sourceFrameCount;
    private double durationSec;
    private int width;
    private int height;
    private int framesProcessed;
    private int framesWithPolyp;
    private double maxConfidence;
    private double processingTimeMs;
    private double averageInferenceMs;
    private double throughputFps;
    private Double aiRoundTripMs;
    private List<TimelinePoint> timeline = new ArrayList<>();
    private List<Segment> segments = new ArrayList<>();
    private String originalVideoFile;
    private String resultVideoFile;
    private long originalSizeBytes;
    private LocalDateTime createdAt;

    public record TimelinePoint(int frameIndex, double timeSec, boolean detected, double confidence, int maskCount) {
    }

    public record Segment(double startSec, double endSec, int frames, double maxConfidence) {
    }

    /** Share of sampled frames with at least one predicted polyp mask, in percent. */
    public double getPositiveFramePercent() {
        return framesProcessed == 0 ? 0 : 100.0 * framesWithPolyp / framesProcessed;
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

    public double getSampleFps() {
        return sampleFps;
    }

    public void setSampleFps(double sampleFps) {
        this.sampleFps = sampleFps;
    }

    public double getRequestedSampleFps() {
        return requestedSampleFps;
    }

    public void setRequestedSampleFps(double requestedSampleFps) {
        this.requestedSampleFps = requestedSampleFps;
    }

    public double getOutputFps() {
        return outputFps;
    }

    public void setOutputFps(double outputFps) {
        this.outputFps = outputFps;
    }

    public int getFramesHeld() {
        return framesHeld;
    }

    public void setFramesHeld(int framesHeld) {
        this.framesHeld = framesHeld;
    }

    /** True when the model ran on every source frame ("Tất cả khung"). */
    public boolean isAllFrames() {
        return requestedSampleFps == 0 && outputFps > 0;
    }

    /** Label of the stored overlay container for the download button. */
    public String getResultFormat() {
        return resultVideoFile != null && resultVideoFile.endsWith(".mp4") ? "MP4" : "WebM";
    }

    public boolean isSampleRateReduced() {
        return sampleRateReduced;
    }

    public void setSampleRateReduced(boolean sampleRateReduced) {
        this.sampleRateReduced = sampleRateReduced;
    }

    public double getSourceFps() {
        return sourceFps;
    }

    public void setSourceFps(double sourceFps) {
        this.sourceFps = sourceFps;
    }

    public int getSourceFrameCount() {
        return sourceFrameCount;
    }

    public void setSourceFrameCount(int sourceFrameCount) {
        this.sourceFrameCount = sourceFrameCount;
    }

    public double getDurationSec() {
        return durationSec;
    }

    public void setDurationSec(double durationSec) {
        this.durationSec = durationSec;
    }

    public int getWidth() {
        return width;
    }

    public void setWidth(int width) {
        this.width = width;
    }

    public int getHeight() {
        return height;
    }

    public void setHeight(int height) {
        this.height = height;
    }

    public int getFramesProcessed() {
        return framesProcessed;
    }

    public void setFramesProcessed(int framesProcessed) {
        this.framesProcessed = framesProcessed;
    }

    public int getFramesWithPolyp() {
        return framesWithPolyp;
    }

    public void setFramesWithPolyp(int framesWithPolyp) {
        this.framesWithPolyp = framesWithPolyp;
    }

    public double getMaxConfidence() {
        return maxConfidence;
    }

    public void setMaxConfidence(double maxConfidence) {
        this.maxConfidence = maxConfidence;
    }

    public double getProcessingTimeMs() {
        return processingTimeMs;
    }

    public void setProcessingTimeMs(double processingTimeMs) {
        this.processingTimeMs = processingTimeMs;
    }

    public double getAverageInferenceMs() {
        return averageInferenceMs;
    }

    public void setAverageInferenceMs(double averageInferenceMs) {
        this.averageInferenceMs = averageInferenceMs;
    }

    public double getThroughputFps() {
        return throughputFps;
    }

    public void setThroughputFps(double throughputFps) {
        this.throughputFps = throughputFps;
    }

    public Double getAiRoundTripMs() {
        return aiRoundTripMs;
    }

    public void setAiRoundTripMs(Double aiRoundTripMs) {
        this.aiRoundTripMs = aiRoundTripMs;
    }

    public List<TimelinePoint> getTimeline() {
        return timeline;
    }

    public void setTimeline(List<TimelinePoint> timeline) {
        this.timeline = timeline == null ? new ArrayList<>() : timeline;
    }

    public List<Segment> getSegments() {
        return segments;
    }

    public void setSegments(List<Segment> segments) {
        this.segments = segments == null ? new ArrayList<>() : segments;
    }

    public String getOriginalVideoFile() {
        return originalVideoFile;
    }

    public void setOriginalVideoFile(String originalVideoFile) {
        this.originalVideoFile = originalVideoFile;
    }

    public String getResultVideoFile() {
        return resultVideoFile;
    }

    public void setResultVideoFile(String resultVideoFile) {
        this.resultVideoFile = resultVideoFile;
    }

    public long getOriginalSizeBytes() {
        return originalSizeBytes;
    }

    public void setOriginalSizeBytes(long originalSizeBytes) {
        this.originalSizeBytes = originalSizeBytes;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
}
