package com.polyp.polypweb.controller;

import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class LegalController {

    @GetMapping("/privacy")
    public String privacy(Model model) {
        model.addAttribute("pageTitle", "Chính sách quyền riêng tư");
        return "legal/privacy";
    }

    @GetMapping("/terms")
    public String terms(Model model) {
        model.addAttribute("pageTitle", "Điều khoản sử dụng");
        return "legal/terms";
    }

    @GetMapping("/disclaimer")
    public String disclaimer(Model model) {
        model.addAttribute("pageTitle", "Cảnh báo nghiên cứu");
        return "legal/disclaimer";
    }
}
