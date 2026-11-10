package com.polyp.polypweb.view;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/** JSON returned by FastAPI {@code POST /video/live} when a real-time playback simulation starts. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record AiLiveVideoStart(String jobId, String modelType, String originalFileName, int requestedSampleFps) {
}
