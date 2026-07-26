package com.polyp.polypweb.controller;

import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.FileStorageService;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.view.ComparisonResultView;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.export.ComparisonMetadataExport;
import com.polyp.polypweb.view.export.DiagnosisMetadataExport;
import com.polyp.polypweb.view.export.ModelMetadataExport;
import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.Optional;

@RestController
public class ExportController {

    private final DiagnosisHistoryService historyService;
    private final ModelComparisonService comparisonService;
    private final FileStorageService storageService;

    public ExportController(
            DiagnosisHistoryService historyService,
            ModelComparisonService comparisonService,
            FileStorageService storageService) {
        this.historyService = historyService;
        this.comparisonService = comparisonService;
        this.storageService = storageService;
    }

    @GetMapping("/diagnoses/{id}/download/original")
    public ResponseEntity<Resource> downloadOriginal(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return download(id, principal, true);
    }

    @GetMapping("/diagnoses/{id}/download/result")
    public ResponseEntity<Resource> downloadResult(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return download(id, principal, false);
    }

    @GetMapping(
            value = "/diagnoses/{id}/metadata.json",
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<DiagnosisMetadataExport> diagnosisMetadata(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return historyService.findDocumentAccessible(
                        id,
                        principal.getUserId(),
                        principal.isAdmin()
                )
                .map(history -> ResponseEntity.ok()
                        .header(
                                HttpHeaders.CONTENT_DISPOSITION,
                                attachment("polypvision_" + safeId(history.getId()) + "_metadata.json")
                        )
                        .body(toDiagnosisMetadata(history)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @GetMapping(
            value = "/comparisons/{comparisonGroupId}/metadata.json",
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<ComparisonMetadataExport> comparisonMetadata(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String comparisonGroupId) {
        return comparisonService.findForUser(
                        comparisonGroupId,
                        principal.getUserId(),
                        principal.isAdmin()
                )
                .map(comparison -> ResponseEntity.ok()
                        .header(
                                HttpHeaders.CONTENT_DISPOSITION,
                                attachment(
                                        "polypvision_comparison_"
                                                + safeId(comparison.getComparisonGroupId())
                                                + ".json"
                                )
                        )
                        .body(toComparisonMetadata(comparison)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    private ResponseEntity<Resource> download(
            String id,
            CurrentUserPrincipal principal,
            boolean original) {
        Optional<DiagnosisHistory> accessible = historyService.findDocumentAccessible(
                id,
                principal.getUserId(),
                principal.isAdmin()
        );
        if (accessible.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        DiagnosisHistory history = accessible.get();
        String mediaUrl = original
                ? history.getOriginalImageUrl()
                : history.getResultImageUrl();
        Optional<Resource> resource = storageService.loadMediaUrl(mediaUrl);
        if (resource.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        String suffix = original ? "original" : "result";
        String extension = mediaUrl != null && mediaUrl.toLowerCase(Locale.ROOT).endsWith(".png")
                ? ".png"
                : ".jpg";
        String downloadName = "polypvision_"
                + modelSlug(history.getModelType())
                + "_"
                + safeId(history.getId())
                + "_"
                + suffix
                + extension;
        return ResponseEntity.ok()
                .contentType(".png".equals(extension) ? MediaType.IMAGE_PNG : MediaType.IMAGE_JPEG)
                .header(HttpHeaders.CONTENT_DISPOSITION, attachment(downloadName))
                .body(resource.get());
    }

    private DiagnosisMetadataExport toDiagnosisMetadata(DiagnosisHistory history) {
        return new DiagnosisMetadataExport(
                history.getId(),
                history.getFileName(),
                history.getModelType(),
                modelCategory(history.getModelType()),
                history.isDetected(),
                history.getLabel(),
                confidenceRatio(history.getConfidence()),
                history.getMaskCount(),
                history.getProcessingTimeMs(),
                null,
                history.getCreatedAt(),
                history.isComparisonResult(),
                history.getComparisonGroupId()
        );
    }

    private ComparisonMetadataExport toComparisonMetadata(ComparisonResultView comparison) {
        return new ComparisonMetadataExport(
                comparison.getComparisonGroupId(),
                comparison.getOriginalFileName(),
                comparison.getCreatedAt(),
                toModelMetadata(comparison.getBaselineResult()),
                toModelMetadata(comparison.getVmambaResult())
        );
    }

    private ModelMetadataExport toModelMetadata(DiagnosisResultView result) {
        return new ModelMetadataExport(
                result.getId(),
                result.getModelType(),
                modelCategory(result.getModelType()),
                result.isDetected(),
                result.getLabel(),
                confidenceRatio(result.getConfidence()),
                result.getMaskCount(),
                result.getProcessingTimeMs(),
                result.getCreatedAt()
        );
    }

    private double confidenceRatio(double confidence) {
        double ratio = confidence > 1 ? confidence / 100.0 : confidence;
        return Math.max(0, Math.min(1, ratio));
    }

    private String modelCategory(String modelType) {
        if (ModelComparisonService.BASELINE_MODEL.equals(modelType)) {
            return "BASELINE";
        }
        if (ModelComparisonService.VMAMBA_MODEL.equals(modelType)) {
            return "VMAMBA";
        }
        return "UNKNOWN";
    }

    private String modelSlug(String modelType) {
        if (modelType == null || modelType.isBlank()) {
            return "model";
        }
        String slug = modelType.toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "-")
                .replaceAll("(^-+|-+$)", "");
        return slug.isBlank() ? "model" : slug;
    }

    private String safeId(String id) {
        if (id == null || id.isBlank()) {
            return "record";
        }
        String safe = id.replaceAll("[^A-Za-z0-9-]", "");
        return safe.isBlank() ? "record" : safe;
    }

    private String attachment(String fileName) {
        return ContentDisposition.attachment()
                .filename(fileName, StandardCharsets.UTF_8)
                .build()
                .toString();
    }
}
