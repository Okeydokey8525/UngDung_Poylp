package com.polyp.polypweb.controller;

import com.polyp.polypweb.view.ResearchMetricView;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.List;

@Controller
public class HomeController {

    @GetMapping("/")
    public String home(Model model) {
        model.addAttribute("pageTitle", "Trang chủ");
        model.addAttribute("activePage", "home");
        model.addAttribute("researchMetrics", List.of(
                new ResearchMetricView("2", "checkpoint hoạt động", "YOLO26n baseline và YOLO26n-VMamba"),
                new ResearchMetricView("≤ 10 MB", "dung lượng ảnh", "Hỗ trợ định dạng JPG, JPEG và PNG"),
                new ResearchMetricView("3 bước", "quy trình trực quan", "Tải ảnh, chọn mô hình và xem kết quả")
        ));
        return "index";
    }

    @GetMapping("/about")
    public String about(Model model) {
        model.addAttribute("pageTitle", "Giới thiệu");
        model.addAttribute("activePage", "about");
        return "about";
    }
}
