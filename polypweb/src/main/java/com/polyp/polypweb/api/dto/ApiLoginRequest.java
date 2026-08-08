package com.polyp.polypweb.api.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.Locale;

public record ApiLoginRequest(
        @NotBlank(message = "Vui lòng nhập email.")
        @Email(message = "Email không hợp lệ.")
        @Size(max = 254, message = "Email quá dài.")
        String email,

        @NotBlank(message = "Vui lòng nhập mật khẩu.")
        String password
) {
    public ApiLoginRequest {
        email = email == null ? null : email.trim().toLowerCase(Locale.ROOT);
    }
}
