package com.polyp.polypweb.dto;

import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public class RegisterForm {

    @NotBlank(message = "Vui lòng nhập họ và tên.")
    @Size(min = 2, max = 100, message = "Họ và tên phải có từ 2 đến 100 ký tự.")
    private String fullName;

    @NotBlank(message = "Vui lòng nhập email.")
    @Email(message = "Địa chỉ email không hợp lệ.")
    @Size(max = 254, message = "Email quá dài.")
    private String email;

    @NotBlank(message = "Vui lòng nhập mật khẩu.")
    @Pattern(
            regexp = "^(?=.*[A-Za-z])(?=.*\\d).{8,72}$",
            message = "Mật khẩu phải có 8–72 ký tự, gồm ít nhất một chữ và một số."
    )
    private String password;

    @NotBlank(message = "Vui lòng xác nhận mật khẩu.")
    private String confirmPassword;

    @AssertTrue(message = "Bạn cần đồng ý với điều khoản sử dụng.")
    private boolean acceptedTerms;

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

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public String getConfirmPassword() {
        return confirmPassword;
    }

    public void setConfirmPassword(String confirmPassword) {
        this.confirmPassword = confirmPassword;
    }

    public boolean isAcceptedTerms() {
        return acceptedTerms;
    }

    public void setAcceptedTerms(boolean acceptedTerms) {
        this.acceptedTerms = acceptedTerms;
    }
}
