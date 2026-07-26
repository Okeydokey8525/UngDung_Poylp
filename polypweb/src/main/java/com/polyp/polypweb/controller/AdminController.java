package com.polyp.polypweb.controller;

import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.exception.AccountOperationException;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.UserAccountService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.context.SecurityContextHolder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

@Controller
public class AdminController {

    private static final Logger LOGGER = LoggerFactory.getLogger(AdminController.class);
    private final UserAccountService userAccountService;

    public AdminController(UserAccountService userAccountService) {
        this.userAccountService = userAccountService;
    }

    @GetMapping("/admin")
    public String adminHome() {
        return "redirect:/admin/users";
    }

    @GetMapping("/admin/users")
    public String users(Model model) {
        model.addAttribute("pageTitle", "Quản trị người dùng");
        model.addAttribute("activePage", "admin");
        model.addAttribute("users", userAccountService.findAllViews());
        model.addAttribute("roles", UserRole.values());
        return "admin/users";
    }

    @PostMapping("/admin/users/{id}/toggle-enabled")
    public String toggleEnabled(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id,
            RedirectAttributes redirectAttributes) {
        try {
            boolean enabled = userAccountService.toggleEnabled(principal.getUserId(), id);
            LOGGER.info(
                    "Admin action=toggle-account actorId={} targetId={} enabled={}",
                    shortId(principal.getUserId()),
                    shortId(id),
                    enabled
            );
            redirectAttributes.addFlashAttribute("flashType", "success");
            redirectAttributes.addFlashAttribute(
                    "flashMessage",
                    enabled ? "Đã mở khóa tài khoản." : "Đã khóa tài khoản."
            );
        } catch (AccountOperationException exception) {
            redirectAttributes.addFlashAttribute("flashType", "warning");
            redirectAttributes.addFlashAttribute("flashMessage", exception.getMessage());
        }
        return "redirect:/admin/users";
    }

    @PostMapping("/admin/users/{id}/role")
    public String changeRole(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id,
            @RequestParam UserRole role,
            RedirectAttributes redirectAttributes,
            HttpServletRequest request) {
        try {
            userAccountService.changeRole(principal.getUserId(), id, role);
            LOGGER.info(
                    "Admin action=change-role actorId={} targetId={} role={}",
                    shortId(principal.getUserId()),
                    shortId(id),
                    role
            );
            redirectAttributes.addFlashAttribute("flashType", "success");
            redirectAttributes.addFlashAttribute("flashMessage", "Đã cập nhật quyền tài khoản.");
            if (principal.getUserId().equals(id) && role == UserRole.USER) {
                SecurityContextHolder.clearContext();
                HttpSession session = request.getSession(false);
                if (session != null) {
                    session.invalidate();
                }
                return "redirect:/login?roleChanged";
            }
        } catch (AccountOperationException exception) {
            redirectAttributes.addFlashAttribute("flashType", "warning");
            redirectAttributes.addFlashAttribute("flashMessage", exception.getMessage());
        }
        return "redirect:/admin/users";
    }

    private String shortId(String value) {
        if (value == null || value.isBlank()) {
            return "unknown";
        }
        return value.length() <= 8 ? value : value.substring(0, 8);
    }
}
