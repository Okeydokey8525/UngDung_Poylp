package com.polyp.polypweb.controller;

import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.PageNavigationView;
import com.polyp.polypweb.view.filter.HistoryFilter;
import org.springframework.data.domain.Page;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

@Controller
public class HistoryController {

    private final DiagnosisHistoryService historyService;

    public HistoryController(DiagnosisHistoryService historyService) {
        this.historyService = historyService;
    }

    @GetMapping("/history")
    public String history(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @ModelAttribute HistoryFilter filter,
            Model model) {
        filter.normalize();
        Page<DiagnosisResultView> historyPage =
                historyService.findHistoryPage(principal.getUserId(), filter);

        model.addAttribute("pageTitle", "Lịch sử phân tích");
        model.addAttribute("activePage", "history");
        model.addAttribute("historyItems", historyPage.getContent());
        model.addAttribute("historyPage", historyPage);
        model.addAttribute("pagination", PageNavigationView.from(historyPage));
        model.addAttribute("filter", filter);
        model.addAttribute("validationMessages", filter.getValidationMessages());
        return "history";
    }

    @PostMapping("/history/{id}/delete")
    public String delete(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id,
            RedirectAttributes redirectAttributes) {
        boolean deleted = historyService.deleteAccessible(
                id,
                principal.getUserId(),
                principal.isAdmin()
        );
        redirectAttributes.addFlashAttribute("flashType", deleted ? "info" : "warning");
        redirectAttributes.addFlashAttribute(
                "flashMessage",
                deleted ? "Đã xóa bản ghi khỏi lịch sử MongoDB." : "Không tìm thấy bản ghi cần xóa."
        );
        return "redirect:/history";
    }
}
