package com.polyp.polypweb.controller;

import com.polyp.polypweb.service.ModelComparisonException;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.view.ComparisonResultView;
import com.polyp.polypweb.view.PageNavigationView;
import com.polyp.polypweb.view.filter.ComparisonHistoryFilter;
import org.springframework.data.domain.Page;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

@Controller
public class ComparisonController {

    private final ModelComparisonService comparisonService;

    public ComparisonController(ModelComparisonService comparisonService) {
        this.comparisonService = comparisonService;
    }

    @GetMapping("/compare")
    public String comparePage(Model model) {
        model.addAttribute("pageTitle", "So sánh mô hình");
        model.addAttribute("activePage", "compare");
        return "compare";
    }

    @PostMapping("/compare")
    public String compare(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @RequestParam(value = "image", required = false) MultipartFile image,
            RedirectAttributes redirectAttributes) {
        if (image == null || image.isEmpty()) {
            redirectAttributes.addFlashAttribute("flashType", "warning");
            redirectAttributes.addFlashAttribute(
                    "flashMessage",
                    "Vui lòng chọn một ảnh nội soi hợp lệ trước khi so sánh."
            );
            return "redirect:/compare";
        }

        try {
            ComparisonResultView comparison =
                    comparisonService.compare(image, principal.getUserId());
            redirectAttributes.addFlashAttribute("flashType", "info");
            redirectAttributes.addFlashAttribute(
                    "flashMessage",
                    "Hai mô hình đã hoàn tất inference và phiên so sánh đã được lưu."
            );
            return "redirect:/comparisons/" + comparison.getComparisonGroupId();
        } catch (ModelComparisonException exception) {
            redirectAttributes.addFlashAttribute("flashType", "warning");
            redirectAttributes.addFlashAttribute("flashMessage", exception.getMessage());
            return "redirect:/compare";
        }
    }

    @GetMapping("/comparisons/{comparisonGroupId}")
    public String comparisonResult(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String comparisonGroupId,
            Model model,
            RedirectAttributes redirectAttributes) {
        return comparisonService.findForUser(
                        comparisonGroupId,
                        principal.getUserId(),
                        principal.isAdmin()
                )
                .map(comparison -> {
                    model.addAttribute("pageTitle", "Kết quả so sánh");
                    model.addAttribute("activePage", "compare");
                    model.addAttribute("comparison", comparison);
                    return "comparison-result";
                })
                .orElseGet(() -> {
                    redirectAttributes.addFlashAttribute("flashType", "warning");
                    redirectAttributes.addFlashAttribute(
                            "flashMessage",
                            "Không tìm thấy phiên so sánh hoàn chỉnh đã yêu cầu."
                    );
                    return "redirect:/comparisons";
                });
    }

    @GetMapping("/comparisons")
    public String comparisonHistory(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @ModelAttribute ComparisonHistoryFilter filter,
            Model model) {
        filter.normalize();
        Page<ComparisonResultView> comparisonPage =
                comparisonService.findHistoryPage(principal.getUserId(), filter);
        model.addAttribute("pageTitle", "Lịch sử so sánh");
        model.addAttribute("activePage", "compare");
        model.addAttribute("comparisons", comparisonPage.getContent());
        model.addAttribute("comparisonPage", comparisonPage);
        model.addAttribute("pagination", PageNavigationView.from(comparisonPage));
        model.addAttribute("filter", filter);
        model.addAttribute("validationMessages", filter.getValidationMessages());
        return "comparison-history";
    }

    @PostMapping("/comparisons/{comparisonGroupId}/delete")
    public String deleteComparison(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String comparisonGroupId,
            RedirectAttributes redirectAttributes) {
        try {
            boolean deleted = comparisonService.deleteForUser(
                    comparisonGroupId,
                    principal.getUserId(),
                    principal.isAdmin()
            );
            redirectAttributes.addFlashAttribute("flashType", deleted ? "info" : "warning");
            redirectAttributes.addFlashAttribute(
                    "flashMessage",
                    deleted
                            ? "Đã xóa toàn bộ phiên so sánh và các file liên quan."
                            : "Không tìm thấy phiên so sánh cần xóa."
            );
        } catch (ModelComparisonException exception) {
            redirectAttributes.addFlashAttribute("flashType", "warning");
            redirectAttributes.addFlashAttribute("flashMessage", exception.getMessage());
        }
        return "redirect:/comparisons";
    }
}
