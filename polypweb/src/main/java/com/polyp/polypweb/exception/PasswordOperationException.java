package com.polyp.polypweb.exception;

public class PasswordOperationException extends AccountOperationException {

    private final String code;

    public PasswordOperationException(String code, String message) {
        super(message);
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
