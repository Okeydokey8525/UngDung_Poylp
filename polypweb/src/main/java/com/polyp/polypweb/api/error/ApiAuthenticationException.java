package com.polyp.polypweb.api.error;

import org.springframework.http.HttpStatus;

public class ApiAuthenticationException extends RuntimeException {

    private final HttpStatus status;
    private final String code;

    public ApiAuthenticationException(HttpStatus status, String code, String message) {
        super(message);
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
