package com.polyp.polypweb.controller;

import com.polyp.polypweb.dto.ChangePasswordForm;
import com.polyp.polypweb.dto.ProfileUpdateForm;
import com.polyp.polypweb.exception.AccountOperationException;
import com.polyp.polypweb.exception.DuplicateEmailException;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.UserAccountService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;

@Controller
public class ProfileController {

    private static final Logger LOGGER = LoggerFactory.getLogger(ProfileController.class);
    private final UserAccountService userAccountService;

    public ProfileController(UserAccountService userAccountService) {
        this.userAccountService = userAccountService;
    }

    @GetMapping("/profile")
    public String profile(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            Model model) {
        ProfileUpdateForm form = new ProfileUpdateForm();
        form.setFullName(principal.getFullName());
        form.setEmail(principal.getEmail());
        model.addAttribute("profileForm", form);
        prepareProfilePage(model, principal);
        return "profile/index";
    }

    @PostMapping("/profile")
    public String updateProfile(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @Valid @ModelAttribute("profileForm") ProfileUpdateForm form,
            BindingResult bindingResult,
            Model model,
            HttpServletRequest request) {
        if (bindingResult.hasErrors()) {
            prepareProfilePage(model, principal);
            return "profile/index";
        }
        try {
            userAccountService.updateProfile(principal.getUserId(), form);
            LOGGER.info("Profile action=update userId={}", shortId(principal.getUserId()));
        } catch (DuplicateEmailException exception) {
            bindingResult.rejectValue("email", "email.duplicate", exception.getMessage());
            prepareProfilePage(model, principal);
            return "profile/index";
        }
        endSession(request);
        return "redirect:/login?profileUpdated";
    }

    @GetMapping("/profile/change-password")
    public String changePasswordPage(Model model) {
        model.addAttribute("passwordForm", new ChangePasswordForm());
        preparePasswordPage(model);
        return "profile/change-password";
    }

    @PostMapping("/profile/change-password")
    public String changePassword(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @Valid @ModelAttribute("passwordForm") ChangePasswordForm form,
            BindingResult bindingResult,
            Model model,
            HttpServletRequest request) {
        if (form.getNewPassword() != null
                && !form.getNewPassword().equals(form.getConfirmNewPassword())) {
            bindingResult.rejectValue(
                    "confirmNewPassword",
                    "password.mismatch",
                    "Mật khẩu mới xác nhận chưa khớp."
            );
        }
        if (bindingResult.hasErrors()) {
            preparePasswordPage(model);
            return "profile/change-password";
        }
        try {
            userAccountService.changePassword(principal.getUserId(), form);
            LOGGER.info("Profile action=change-password userId={}", shortId(principal.getUserId()));
        } catch (AccountOperationException exception) {
            bindingResult.reject("password.invalid", exception.getMessage());
            preparePasswordPage(model);
            return "profile/change-password";
        }
        endSession(request);
        return "redirect:/login?passwordChanged";
    }

    private void prepareProfilePage(Model model, CurrentUserPrincipal principal) {
        model.addAttribute("pageTitle", "Hồ sơ");
        model.addAttribute("activePage", "profile");
        model.addAttribute("account", userAccountService.findViewById(principal.getUserId()));
    }

    private void preparePasswordPage(Model model) {
        model.addAttribute("pageTitle", "Đổi mật khẩu");
        model.addAttribute("activePage", "profile");
    }

    private void endSession(HttpServletRequest request) {
        SecurityContextHolder.clearContext();
        HttpSession session = request.getSession(false);
        if (session != null) {
            session.invalidate();
        }
    }

    private String shortId(String value) {
        if (value == null || value.isBlank()) {
            return "unknown";
        }
        return value.length() <= 8 ? value : value.substring(0, 8);
    }
}
