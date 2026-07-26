package com.polyp.polypweb.controller;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class AccessDeniedController {

    @GetMapping("/error/403")
    public String accessDenied(Model model) {
        model.addAttribute("pageTitle", "Không có quyền truy cập");
        return "error/403";
    }
}
