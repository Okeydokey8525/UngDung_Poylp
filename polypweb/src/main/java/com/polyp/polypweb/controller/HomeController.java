package com.polyp.polypweb.controller;

import com.polyp.polypweb.view.ResearchMetricView;
import com.polyp.polypweb.service.DiagnosisModel;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.List;
import java.util.Arrays;
import java.util.stream.Collectors;

@Controller
public class HomeController {

    @GetMapping("/")
    public String home(Model model) {
        model.addAttribute("pageTitle", "Trang chủ");
        model.addAttribute("activePage", "home");
        model.addAttribute("researchMetrics", List.of(
                new ResearchMetricView(
                        Integer.toString(DiagnosisModel.values().length),
                        "mô hình được hỗ trợ",
                        Arrays.stream(DiagnosisModel.values())
                                .map(DiagnosisModel::getModelType)
                                .collect(Collectors.joining(" và "))
                ),
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
