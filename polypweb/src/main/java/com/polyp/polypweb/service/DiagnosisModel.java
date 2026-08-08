package com.polyp.polypweb.service;

import java.util.Arrays;
import java.util.Optional;

public enum DiagnosisModel {

    BASELINE("YOLO26n-seg", "BASELINE"),
    VMAMBA("YOLO26n-VMamba-seg", "VMAMBA");

    private final String modelType;
    private final String category;

    DiagnosisModel(String modelType, String category) {
        this.modelType = modelType;
        this.category = category;
    }

    public String getModelType() {
        return modelType;
    }

    public String getCategory() {
        return category;
    }

    public static Optional<DiagnosisModel> fromModelType(String value) {
        if (value == null) {
            return Optional.empty();
        }
        String normalized = value.trim();
        return Arrays.stream(values())
                .filter(model -> model.modelType.equals(normalized))
                .findFirst();
    }
}
