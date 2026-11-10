package com.polyp.polypweb.view;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.polyp.polypweb.document.VideoAnalysis;

import java.util.List;

/** JSON returned by FastAPI {@code POST /video/predict}. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record AiVideoPredictionResponse(
        boolean success,
        String modelType,
        String originalFileName,
        double sourceFps,
        int sourceFrameCount,
        double durationSec,
        int width,
        int height,
        double sampleFps,
        double requestedSampleFps,
        boolean sampleRateReduced,
        Double outputFps,
        Integer framesWritten,
        Integer framesHeld,
        int framesProcessed,
        int framesWithPolyp,
        double maxConfidence,
        double processingTimeMs,
        double averageInferenceMs,
        double throughputFps,
        List<VideoAnalysis.TimelinePoint> timeline,
        List<VideoAnalysis.Segment> segments,
        String resultVideoBase64,
        String resultVideoMimeType,
        String message,
        Double aiRoundTripMs) {

    public AiVideoPredictionResponse withAiRoundTripMs(double roundTripMs) {
        return new AiVideoPredictionResponse(
                success, modelType, originalFileName, sourceFps, sourceFrameCount, durationSec, width, height,
                sampleFps, requestedSampleFps, sampleRateReduced, outputFps, framesWritten, framesHeld, framesProcessed, framesWithPolyp, maxConfidence, processingTimeMs, averageInferenceMs,
                throughputFps, timeline, segments, resultVideoBase64, resultVideoMimeType, message, roundTripMs
        );
    }
}
