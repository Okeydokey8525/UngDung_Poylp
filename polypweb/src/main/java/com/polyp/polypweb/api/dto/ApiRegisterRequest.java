package com.polyp.polypweb.api.dto;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.Locale;

public record ApiRegisterRequest(
        @NotBlank(message = "Vui lòng nhập họ và tên.")
        @Size(min = 2, max = 100, message = "Họ và tên phải có từ 2 đến 100 ký tự.")
        String fullName,

        @NotBlank(message = "Vui lòng nhập email.")
        @Email(message = "Email không hợp lệ.")
        @Size(max = 254, message = "Email quá dài.")
        String email,

        @NotBlank(message = "Vui lòng nhập mật khẩu.")
        @Pattern(
                regexp = "^(?=.*[A-Za-z])(?=.*\\d).{8,72}$",
                message = "Mật khẩu phải có 8–72 ký tự, gồm ít nhất một chữ và một số."
        )
        String password,

        @NotBlank(message = "Vui lòng xác nhận mật khẩu.")
        String confirmPassword,

        @AssertTrue(message = "Bạn cần đồng ý với điều khoản sử dụng.")
        boolean acceptedTerms
) {
    public ApiRegisterRequest {
        fullName = fullName == null ? null : fullName.trim().replaceAll("\\s+", " ");
        email = email == null ? null : email.trim().toLowerCase(Locale.ROOT);
    }
}
