package com.polyp.polypweb.view.filter;

import java.util.Optional;

public enum DetectionFilterOption {

    ALL("ALL", null),
    DETECTED("true", true),
    NOT_DETECTED("false", false);

    private final String queryValue;
    private final Boolean detected;

    DetectionFilterOption(String queryValue, Boolean detected) {
        this.queryValue = queryValue;
        this.detected = detected;
    }

    public String getQueryValue() {
        return queryValue;
    }

    public Boolean getDetected() {
        return detected;
    }

    public boolean isAll() {
        return this == ALL;
    }

    public static Optional<DetectionFilterOption> parse(String value) {
        if (value == null || value.isBlank() || "ALL".equalsIgnoreCase(value.trim())) {
            return Optional.of(ALL);
        }
        String normalized = value.trim();
        if ("true".equalsIgnoreCase(normalized) || "detected".equalsIgnoreCase(normalized)) {
            return Optional.of(DETECTED);
        }
        if ("false".equalsIgnoreCase(normalized)
                || "not-detected".equalsIgnoreCase(normalized)
                || "not_detected".equalsIgnoreCase(normalized)) {
            return Optional.of(NOT_DETECTED);
        }
        return Optional.empty();
    }
}
