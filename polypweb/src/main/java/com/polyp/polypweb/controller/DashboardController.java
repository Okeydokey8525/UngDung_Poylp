package com.polyp.polypweb.controller;

import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DashboardService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class DashboardController {

    private final DashboardService dashboardService;

    public DashboardController(DashboardService dashboardService) {
        this.dashboardService = dashboardService;
    }

    @GetMapping("/dashboard")
    public String userDashboard(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            Model model) {
        model.addAttribute("pageTitle", "Tổng quan hoạt động");
        model.addAttribute(
                "dashboard",
                dashboardService.userDashboard(principal.getUserId(), principal.getFullName())
        );
        return "dashboard";
    }

    @GetMapping("/admin/dashboard")
    public String adminDashboard(Model model) {
        model.addAttribute("pageTitle", "Dashboard quản trị");
        model.addAttribute("dashboard", dashboardService.adminDashboard());
        return "admin/dashboard";
    }
}
