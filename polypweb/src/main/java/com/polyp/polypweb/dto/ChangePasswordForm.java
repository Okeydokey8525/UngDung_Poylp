package com.polyp.polypweb.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public class ChangePasswordForm {

    @NotBlank(message = "Vui lòng nhập mật khẩu hiện tại.")
    private String currentPassword;

    @NotBlank(message = "Vui lòng nhập mật khẩu mới.")
    @Pattern(
            regexp = "^(?=.*[A-Za-z])(?=.*\\d).{8,72}$",
            message = "Mật khẩu mới phải có 8–72 ký tự, gồm ít nhất một chữ và một số."
    )
    private String newPassword;

    @NotBlank(message = "Vui lòng xác nhận mật khẩu mới.")
    private String confirmNewPassword;

    public String getCurrentPassword() {
        return currentPassword;
    }

    public void setCurrentPassword(String currentPassword) {
        this.currentPassword = currentPassword;
    }

    public String getNewPassword() {
        return newPassword;
    }

    public void setNewPassword(String newPassword) {
        this.newPassword = newPassword;
    }

    public String getConfirmNewPassword() {
        return confirmNewPassword;
    }

    public void setConfirmNewPassword(String confirmNewPassword) {
        this.confirmNewPassword = confirmNewPassword;
    }
}
