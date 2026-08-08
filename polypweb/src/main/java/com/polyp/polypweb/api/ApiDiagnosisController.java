package com.polyp.polypweb.api;

import com.polyp.polypweb.api.dto.ApiDiagnosisMetadataResponse;
import com.polyp.polypweb.api.dto.ApiDiagnosisResponse;
import com.polyp.polypweb.api.dto.ApiDiagnosisHistoryItemResponse;
import com.polyp.polypweb.api.dto.ApiPagedResponse;
import com.polyp.polypweb.api.error.ApiValidationException;
import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DiagnosisAnalysisService;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.FileStorageService;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;

import com.polyp.polypweb.view.filter.HistoryFilter;

@RestController
@RequestMapping(value = "/api/v1/diagnoses")
public class ApiDiagnosisController {

    private final DiagnosisAnalysisService analysisService;
    private final DiagnosisHistoryService historyService;
    private final FileStorageService storageService;

    public ApiDiagnosisController(
            DiagnosisAnalysisService analysisService,
            DiagnosisHistoryService historyService,
            FileStorageService storageService) {
        this.analysisService = analysisService;
        this.historyService = historyService;
        this.storageService = storageService;
    }

    @PostMapping(
            consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<ApiDiagnosisResponse> create(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @RequestParam(value = "image", required = false) MultipartFile image,
            @RequestParam(value = "modelType", required = false) String modelType) {
        ApiDiagnosisResponse response = ApiDiagnosisResponse.from(
                analysisService.analyze(image, modelType, principal.getUserId())
        );
        return ResponseEntity.status(HttpStatus.CREATED)
                .cacheControl(CacheControl.noStore())
                .body(response);
    }

    @GetMapping(produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiPagedResponse<ApiDiagnosisHistoryItemResponse>> history(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @ModelAttribute HistoryFilter filter) {
        filter.normalize();
        validateDates(filter.hasInvalidDateFormat(), filter.hasInvalidDateRange());
        var page = historyService.findHistoryPage(principal.getUserId(), filter)
                .map(ApiDiagnosisHistoryItemResponse::from);
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(ApiPagedResponse.from(page));
    }

    @GetMapping(value = "/{id}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiDiagnosisResponse> detail(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        DiagnosisHistory history = singleDiagnosis(id, principal);
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(ApiDiagnosisResponse.from(historyService.toView(history)));
    }

    @GetMapping("/{id}/images/original")
    public ResponseEntity<Resource> originalImage(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return image(id, principal, true);
    }

    @GetMapping("/{id}/images/result")
    public ResponseEntity<Resource> resultImage(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return image(id, principal, false);
    }

    @GetMapping(value = "/{id}/metadata", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiDiagnosisMetadataResponse> metadata(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        ApiDiagnosisResponse diagnosis = ApiDiagnosisResponse.from(
                historyService.toView(singleDiagnosis(id, principal))
        );
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(ApiDiagnosisMetadataResponse.from(diagnosis));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        DiagnosisHistory history = accessible(id, principal);
        if (history.isComparisonResult()) {
            throw new DiagnosisOperationException(
                    HttpStatus.CONFLICT,
                    "COMPARISON_RESULT_REQUIRES_GROUP_DELETE",
                    "Kết quả thuộc phiên so sánh phải được xóa theo cả nhóm."
            );
        }
        boolean deleted = historyService.deleteAccessible(
                id,
                principal.getUserId(),
                principal.isAdmin()
        );
        if (!deleted) {
            throw notFound();
        }
        return ResponseEntity.noContent()
                .cacheControl(CacheControl.noStore())
                .build();
    }

    private ResponseEntity<Resource> image(
            String id,
            CurrentUserPrincipal principal,
            boolean original) {
        DiagnosisHistory history = accessible(id, principal);
        String mediaUrl = original
                ? history.getOriginalImageUrl()
                : history.getResultImageUrl();
        Resource resource = storageService.loadMediaUrl(mediaUrl)
                .orElseThrow(() -> new DiagnosisOperationException(
                        HttpStatus.NOT_FOUND,
                        "FILE_NOT_FOUND",
                        "Không tìm thấy file ảnh đã yêu cầu."
                ));
        ResponseEntity.BodyBuilder response = ResponseEntity.ok()
                .contentType(mediaType(mediaUrl))
                .cacheControl(CacheControl.maxAge(Duration.ofHours(1)).cachePrivate())
                .header("X-Content-Type-Options", "nosniff");
        try {
            long length = resource.contentLength();
            if (length >= 0) {
                response.contentLength(length);
            }
        } catch (IOException ignored) {
            // Streaming still remains safe when the resource cannot report its length.
        }
        return response.body(resource);
    }

    private DiagnosisHistory singleDiagnosis(
            String id,
            CurrentUserPrincipal principal) {
        DiagnosisHistory history = accessible(id, principal);
        if (history.isComparisonResult()) {
            throw notFound();
        }
        return history;
    }

    private DiagnosisHistory accessible(
            String id,
            CurrentUserPrincipal principal) {
        return historyService.findDocumentAccessible(
                        id,
                        principal.getUserId(),
                        principal.isAdmin()
                )
                .orElseThrow(this::notFound);
    }

    private MediaType mediaType(String mediaUrl) {
        return mediaUrl != null && mediaUrl.toLowerCase().endsWith(".png")
                ? MediaType.IMAGE_PNG
                : MediaType.IMAGE_JPEG;
    }

    private DiagnosisOperationException notFound() {
        return new DiagnosisOperationException(
                HttpStatus.NOT_FOUND,
                "RESOURCE_NOT_FOUND",
                "Không tìm thấy kết quả phân tích."
        );
    }

    private void validateDates(boolean invalidFormat, boolean invalidRange) {
        Map<String, String> errors = new LinkedHashMap<>();
        if (invalidFormat) {
            errors.put("date", "Ngày phải có định dạng yyyy-MM-dd.");
        }
        if (invalidRange) {
            errors.put("dateRange", "Ngày bắt đầu không được sau ngày kết thúc.");
        }
        if (!errors.isEmpty()) {
            throw new ApiValidationException(errors);
        }
    }
}
