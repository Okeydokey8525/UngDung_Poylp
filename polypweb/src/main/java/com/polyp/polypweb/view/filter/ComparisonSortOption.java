package com.polyp.polypweb.view.filter;

import java.util.Arrays;
import java.util.Optional;

public enum ComparisonSortOption {

    NEWEST("newest", "createdAt", -1),
    OLDEST("oldest", "createdAt", 1),
    BASELINE_CONFIDENCE_DESC("baseline-confidence-desc", "baseline.confidence", -1),
    VMAMBA_CONFIDENCE_DESC("vmamba-confidence-desc", "vmamba.confidence", -1),
    TOTAL_PROCESSING_DESC("total-processing-desc", "totalProcessingTimeMs", -1),
    TOTAL_PROCESSING_ASC("total-processing-asc", "totalProcessingTimeMs", 1);

    private final String queryValue;
    private final String field;
    private final int direction;

    ComparisonSortOption(String queryValue, String field, int direction) {
        this.queryValue = queryValue;
        this.field = field;
        this.direction = direction;
    }

    public String getQueryValue() {
        return queryValue;
    }

    public String getField() {
        return field;
    }

    public int getDirection() {
        return direction;
    }

    public static Optional<ComparisonSortOption> parse(String value) {
        if (value == null || value.isBlank()) {
            return Optional.of(NEWEST);
        }
        return Arrays.stream(values())
                .filter(option -> option.queryValue.equalsIgnoreCase(value.trim()))
                .findFirst();
    }
}
