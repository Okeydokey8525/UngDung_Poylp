package com.polyp.polypweb.view.filter;

import java.util.Arrays;
import java.util.Optional;

public enum ModelFilterOption {

    ALL("ALL", null),
    BASELINE("YOLO26n-seg", "YOLO26n-seg"),
    VMAMBA("YOLO26n-VMamba-seg", "YOLO26n-VMamba-seg");

    private final String queryValue;
    private final String modelType;

    ModelFilterOption(String queryValue, String modelType) {
        this.queryValue = queryValue;
        this.modelType = modelType;
    }

    public String getQueryValue() {
        return queryValue;
    }

    public String getModelType() {
        return modelType;
    }

    public boolean isAll() {
        return this == ALL;
    }

    public static Optional<ModelFilterOption> parse(String value) {
        if (value == null || value.isBlank()) {
            return Optional.of(ALL);
        }
        return Arrays.stream(values())
                .filter(option -> option.queryValue.equalsIgnoreCase(value.trim()))
                .findFirst();
    }
}
