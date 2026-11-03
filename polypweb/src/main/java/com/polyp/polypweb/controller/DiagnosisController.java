package com.polyp.polypweb.controller;

import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.ModelOptionView;
import com.polyp.polypweb.service.DiagnosisAnalysisService;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.DiagnosisModel;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;

@Controller
public class DiagnosisController {

    private static final Logger LOGGER = LoggerFactory.getLogger(DiagnosisController.class);
    private static final Set<String> ACTIVE_MODEL_CODES = Set.of(
            "yolo26s-seg",
            "yolo26s-tsvm-fp32-seg"
    );
    private final DiagnosisHistoryService historyService;
    private final DiagnosisAnalysisService analysisService;

    private static final List<ModelOptionView> MODEL_OPTIONS = List.of(
            baseline("yolo26s-seg", "YOLO26s-seg", "Mô hình cơ bản dùng đối chiếu thực nghiệm BG20."),
            vmamba("yolo26s-tsvm-fp32-seg", "YOLO26s-TSVM-FP32-seg", "C2TSVMamba tại tầng 10 và suy luận FP32.")
    );
    public DiagnosisController(
            DiagnosisHistoryService historyService,
            DiagnosisAnalysisService analysisService) {
        this.historyService = historyService;
        this.analysisService = analysisService;
    }

    @GetMapping("/diagnose")
    public String diagnose(Model model) {
        addDiagnosePageData(model);
        return "diagnose";
    }

    @PostMapping({"/diagnose", "/diagnose/mock"})
    public String diagnoseImage(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @RequestParam(value = "image", required = false) MultipartFile image,
            @RequestParam(value = "modelType", defaultValue = "yolo26s-seg") String modelType,
            RedirectAttributes redirectAttributes) {
        if (image == null || image.isEmpty()) {
            redirectAttributes.addFlashAttribute("flashType", "warning");
            redirectAttributes.addFlashAttribute("flashMessage", "Vui lòng chọn một ảnh nội soi hợp lệ trước khi phân tích.");
            return "redirect:/diagnose";
        }

        if (!ACTIVE_MODEL_CODES.contains(modelType)) {
            redirectAttributes.addFlashAttribute("flashType", "warning");
            redirectAttributes.addFlashAttribute(
                    "flashMessage",
                    "Giai đoạn 3D chỉ kích hoạt YOLO26s-seg và YOLO26s-TSVM-FP32-seg."
            );
            return "redirect:/diagnose";
        }

        String selectedModel = MODEL_OPTIONS.stream()
                .filter(option -> option.getCode().equals(modelType))
                .map(ModelOptionView::getName)
                .findFirst()
                .orElse(MODEL_OPTIONS.get(0).getName());

        DiagnosisResultView savedResult;
        try {
            savedResult = analysisService.analyze(image, selectedModel, principal.getUserId());
        } catch (DiagnosisOperationException exception) {
            LOGGER.warn(
                    "Diagnosis rejected userId={} modelType={} code={}",
                    shortId(principal.getUserId()),
                    selectedModel,
                    exception.getCode()
            );
            redirectAttributes.addFlashAttribute("flashType", "warning");
            redirectAttributes.addFlashAttribute("flashMessage", exception.getMessage());
            return "redirect:/diagnose";
        }

        redirectAttributes.addFlashAttribute("flashType", "info");
        redirectAttributes.addFlashAttribute(
                "flashMessage",
                selectedModel + " đã hoàn tất inference; ảnh và metadata đã được lưu lâu dài."
        );
        return "redirect:/diagnoses/" + savedResult.getId();
    }

    @GetMapping("/diagnoses/{id}")
    public String resultById(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id,
            Model model,
            RedirectAttributes redirectAttributes) {
        return historyService.findByIdAccessible(id, principal.getUserId(), principal.isAdmin())
                .map(result -> {
                    addResultPageData(model, result);
                    return "diagnosis-result";
                })
                .orElseGet(() -> {
                    redirectAttributes.addFlashAttribute("flashType", "warning");
                    redirectAttributes.addFlashAttribute("flashMessage", "Không tìm thấy bản ghi lịch sử đã yêu cầu.");
                    return "redirect:/history";
                });
    }

    @GetMapping("/diagnoses/demo")
    public String demoResult(Model model) {
        DiagnosisResultView result = createMockResult(
                "PV-DEMO-001",
                "noi-soi-dai-trang-demo.jpg",
                DiagnosisModel.VMAMBA.getModelType(),
                true,
                93.4,
                118.6,
                LocalDateTime.now().minusMinutes(8)
        );
        addResultPageData(model, result);
        return "diagnosis-result";
    }

    private void addDiagnosePageData(Model model) {
        model.addAttribute("pageTitle", "Phân tích ảnh");
        model.addAttribute("activePage", "diagnose");
        model.addAttribute("modelOptions", MODEL_OPTIONS);
    }

    private void addResultPageData(Model model, DiagnosisResultView result) {
        model.addAttribute("pageTitle", "Kết quả phân tích");
        model.addAttribute("activePage", "diagnose");
        model.addAttribute("result", result);
        model.addAttribute(
                "vmambaModel",
                DiagnosisModel.fromModelType(result.getModelType())
                        .filter(selected -> selected == DiagnosisModel.VMAMBA)
                        .isPresent()
        );
        model.addAttribute("unknownModel", DiagnosisModel.fromModelType(result.getModelType()).isEmpty());
    }

    private DiagnosisResultView createMockResult(
            String id,
            String fileName,
            String modelType,
            boolean detected,
            double confidence,
            double processingTime,
            LocalDateTime createdAt) {
        return new DiagnosisResultView(
                id,
                "",
                "",
                fileName,
                modelType,
                detected,
                detected ? "polyp" : "Không có",
                confidence,
                processingTime,
                "Ảnh minh họa",
                createdAt,
                true
        );
    }

    private static ModelOptionView baseline(String code, String name, String description) {
        return new ModelOptionView(
                code,
                name,
                description,
                false,
                ACTIVE_MODEL_CODES.contains(code)
        );
    }

    private static ModelOptionView vmamba(String code, String name, String description) {
        return new ModelOptionView(
                code,
                name,
                description,
                true,
                ACTIVE_MODEL_CODES.contains(code)
        );
    }

    private String shortId(String value) {
        if (value == null || value.isBlank()) {
            return "unknown";
        }
        return value.length() <= 8 ? value : value.substring(0, 8);
    }
}
