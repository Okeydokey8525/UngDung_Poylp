package com.polyp.polypweb.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public class ProfileUpdateForm {

    @NotBlank(message = "Vui lòng nhập họ và tên.")
    @Size(min = 2, max = 100, message = "Họ và tên phải có từ 2 đến 100 ký tự.")
    private String fullName;

    @NotBlank(message = "Vui lòng nhập email.")
    @Email(message = "Địa chỉ email không hợp lệ.")
    @Size(max = 254, message = "Email quá dài.")
    private String email;

    public String getFullName() {
        return fullName;
    }

    public void setFullName(String fullName) {
        this.fullName = fullName;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }
}
