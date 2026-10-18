package com.polyp.polypweb.view.filter;

import java.util.Arrays;
import java.util.Optional;

public enum ModelFilterOption {

    ALL("ALL", null),
    BASELINE("YOLO26s-seg", "YOLO26s-seg"),
    VMAMBA("YOLO26s-TSVM-FP32-seg", "YOLO26s-TSVM-FP32-seg");

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
