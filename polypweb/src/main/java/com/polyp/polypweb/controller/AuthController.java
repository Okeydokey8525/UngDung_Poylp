package com.polyp.polypweb.controller;

import com.polyp.polypweb.dto.RegisterForm;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.exception.AccountOperationException;
import com.polyp.polypweb.exception.DuplicateEmailException;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.UserAccountService;
import jakarta.validation.Valid;
import org.springframework.security.core.Authentication;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PostMapping;

@Controller
public class AuthController {

    private static final Logger LOGGER = LoggerFactory.getLogger(AuthController.class);
    private final UserAccountService userAccountService;

    public AuthController(UserAccountService userAccountService) {
        this.userAccountService = userAccountService;
    }

    @GetMapping("/login")
    public String login(Authentication authentication, Model model) {
        if (isSignedIn(authentication)) {
            return "redirect:/profile";
        }
        model.addAttribute("pageTitle", "Đăng nhập");
        model.addAttribute("activePage", "login");
        return "auth/login";
    }

    @GetMapping("/register")
    public String register(Authentication authentication, Model model) {
        if (isSignedIn(authentication)) {
            return "redirect:/profile";
        }
        if (!model.containsAttribute("registerForm")) {
            model.addAttribute("registerForm", new RegisterForm());
        }
        prepareRegisterPage(model);
        return "auth/register";
    }

    @PostMapping("/register")
    public String register(
            @Valid @ModelAttribute("registerForm") RegisterForm form,
            BindingResult bindingResult,
            Model model) {
        if (form.getPassword() != null
                && !form.getPassword().equals(form.getConfirmPassword())) {
            bindingResult.rejectValue(
                    "confirmPassword",
                    "password.mismatch",
                    "Mật khẩu xác nhận chưa khớp."
            );
        }
        if (bindingResult.hasErrors()) {
            prepareRegisterPage(model);
            return "auth/register";
        }
        try {
            UserAccount account = userAccountService.register(form);
            LOGGER.info("Đăng ký tài khoản userId={} thành công", shortId(account.getId()));
        } catch (DuplicateEmailException exception) {
            bindingResult.rejectValue("email", "email.duplicate", exception.getMessage());
            prepareRegisterPage(model);
            return "auth/register";
        } catch (AccountOperationException exception) {
            bindingResult.reject("register.invalid", exception.getMessage());
            prepareRegisterPage(model);
            return "auth/register";
        }
        return "redirect:/login?registered";
    }

    private void prepareRegisterPage(Model model) {
        model.addAttribute("pageTitle", "Đăng ký");
        model.addAttribute("activePage", "register");
    }

    private boolean isSignedIn(Authentication authentication) {
        return authentication != null
                && authentication.isAuthenticated()
                && authentication.getPrincipal() instanceof CurrentUserPrincipal;
    }

    private String shortId(String value) {
        if (value == null || value.isBlank()) {
            return "unknown";
        }
        return value.length() <= 8 ? value : value.substring(0, 8);
    }
}
