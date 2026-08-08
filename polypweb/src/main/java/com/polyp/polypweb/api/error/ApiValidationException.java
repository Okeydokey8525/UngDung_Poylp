package com.polyp.polypweb.api.error;

import java.util.Map;

public class ApiValidationException extends RuntimeException {

    private final Map<String, String> fieldErrors;

    public ApiValidationException(Map<String, String> fieldErrors) {
        super("Dữ liệu không hợp lệ.");
        this.fieldErrors = Map.copyOf(fieldErrors);
    }

    public Map<String, String> getFieldErrors() {
        return fieldErrors;
    }
}
