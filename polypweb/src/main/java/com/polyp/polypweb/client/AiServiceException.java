package com.polyp.polypweb.client;

public class AiServiceException extends RuntimeException {

    private final String code;

    public AiServiceException(String message) {
        this("AI_SERVICE_UNAVAILABLE", message, null);
    }

    public AiServiceException(String message, Throwable cause) {
        this("AI_SERVICE_UNAVAILABLE", message, cause);
    }

    public AiServiceException(String code, String message) {
        this(code, message, null);
    }

    public AiServiceException(String code, String message, Throwable cause) {
        super(message, cause);
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
