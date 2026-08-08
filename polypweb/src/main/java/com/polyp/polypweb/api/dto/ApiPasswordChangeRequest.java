package com.polyp.polypweb.api.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record ApiPasswordChangeRequest(
        @NotBlank(message = "Vui lòng nhập mật khẩu hiện tại.")
        String currentPassword,

        @NotBlank(message = "Vui lòng nhập mật khẩu mới.")
        @Pattern(
                regexp = "^(?=.*[A-Za-z])(?=.*\\d).{8,72}$",
                message = "Mật khẩu mới phải có 8–72 ký tự, gồm ít nhất một chữ và một số."
        )
        String newPassword,

        @NotBlank(message = "Vui lòng xác nhận mật khẩu mới.")
        String confirmPassword
) {
}
