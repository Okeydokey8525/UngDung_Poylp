package com.polyp.polypweb.view.filter;

import org.springframework.data.domain.Sort;

import java.util.Arrays;
import java.util.Optional;

public enum HistorySortOption {

    NEWEST("newest", Sort.Direction.DESC, "createdAt"),
    OLDEST("oldest", Sort.Direction.ASC, "createdAt"),
    CONFIDENCE_DESC("confidence-desc", Sort.Direction.DESC, "confidence"),
    CONFIDENCE_ASC("confidence-asc", Sort.Direction.ASC, "confidence"),
    PROCESSING_DESC("processing-desc", Sort.Direction.DESC, "processingTimeMs"),
    PROCESSING_ASC("processing-asc", Sort.Direction.ASC, "processingTimeMs");

    private final String queryValue;
    private final Sort.Direction direction;
    private final String field;

    HistorySortOption(String queryValue, Sort.Direction direction, String field) {
        this.queryValue = queryValue;
        this.direction = direction;
        this.field = field;
    }

    public String getQueryValue() {
        return queryValue;
    }

    public Sort toSort() {
        return Sort.by(direction, field).and(Sort.by(direction, "_id"));
    }

    public static Optional<HistorySortOption> parse(String value) {
        if (value == null || value.isBlank()) {
            return Optional.of(NEWEST);
        }
        return Arrays.stream(values())
                .filter(option -> option.queryValue.equalsIgnoreCase(value.trim()))
                .findFirst();
    }
}
