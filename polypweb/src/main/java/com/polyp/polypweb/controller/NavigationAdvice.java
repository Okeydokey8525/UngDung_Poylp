package com.polyp.polypweb.controller;

import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.view.UserAccountView;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ModelAttribute;

@ControllerAdvice
public class NavigationAdvice {

    @ModelAttribute("activeNav")
    public String activeNavigation(HttpServletRequest request) {
        String path = request.getRequestURI();
        String contextPath = request.getContextPath();
        if (!contextPath.isEmpty() && path.startsWith(contextPath)) {
            path = path.substring(contextPath.length());
        }

        if ("/".equals(path)) {
            return "home";
        }
        if ("/dashboard".equals(path)) {
            return "dashboard";
        }
        if ("/admin/dashboard".equals(path)) {
            return "admin-dashboard";
        }
        if ("/admin/users".equals(path)) {
            return "admin-users";
        }
        if ("/diagnose".equals(path) || path.startsWith("/diagnoses/")) {
            return "diagnose";
        }
        if ("/compare".equals(path)) {
            return "compare";
        }
        if ("/comparisons".equals(path) || path.startsWith("/comparisons/")) {
            return "comparisons";
        }
        if ("/history".equals(path)) {
            return "history";
        }
        if ("/about".equals(path)) {
            return "about";
        }
        return "";
    }

    @ModelAttribute("currentUser")
    public UserAccountView currentUser(Authentication authentication) {
        if (authentication == null
                || !authentication.isAuthenticated()
                || !(authentication.getPrincipal() instanceof CurrentUserPrincipal principal)) {
            return null;
        }
        return new UserAccountView(
                principal.getUserId(),
                principal.getFullName(),
                principal.getEmail(),
                principal.getRole(),
                principal.isEnabled(),
                null
        );
    }
}
