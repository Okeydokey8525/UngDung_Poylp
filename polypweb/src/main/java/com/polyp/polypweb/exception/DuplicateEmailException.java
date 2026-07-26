package com.polyp.polypweb.exception;

public class DuplicateEmailException extends RuntimeException {

    public DuplicateEmailException() {
        super("Email đã được sử dụng.");
    }
}
