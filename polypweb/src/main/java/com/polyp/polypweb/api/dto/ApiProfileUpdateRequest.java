package com.polyp.polypweb.api.dto;

import com.polyp.polypweb.service.UserAccountService;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record ApiProfileUpdateRequest(
        @NotBlank(message = "Vui lòng nhập họ và tên.")
        @Size(min = 2, max = 100, message = "Họ và tên phải có từ 2 đến 100 ký tự.")
        String fullName,

        @NotBlank(message = "Vui lòng nhập email.")
        @Email(message = "Địa chỉ email không hợp lệ.")
        @Size(max = 254, message = "Email quá dài.")
        String email
) {
    public ApiProfileUpdateRequest {
        fullName = fullName == null ? null : fullName.trim().replaceAll("\\s+", " ");
        email = email == null ? null : UserAccountService.normalizeEmail(email);
    }
}
