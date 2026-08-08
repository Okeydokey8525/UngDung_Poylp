package com.polyp.polypweb.service;

import org.springframework.http.HttpStatus;

public class ModelComparisonException extends RuntimeException {

    private final HttpStatus status;
    private final String code;

    public ModelComparisonException(String message) {
        this(HttpStatus.INTERNAL_SERVER_ERROR, "COMPARISON_FAILED", message, null);
    }

    public ModelComparisonException(String message, Throwable cause) {
        this(HttpStatus.INTERNAL_SERVER_ERROR, "COMPARISON_FAILED", message, cause);
    }

    public ModelComparisonException(HttpStatus status, String code, String message) {
        this(status, code, message, null);
    }

    public ModelComparisonException(
            HttpStatus status,
            String code,
            String message,
            Throwable cause) {
        super(message, cause);
        this.status = status;
        this.code = code;
    }

    public HttpStatus getStatus() {
        return status;
    }

    public String getCode() {
        return code;
    }
}
