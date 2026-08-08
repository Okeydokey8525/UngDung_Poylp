package com.polyp.polypweb.api;

import com.polyp.polypweb.api.dto.ApiComparisonMetadataResponse;
import com.polyp.polypweb.api.dto.ApiComparisonResponse;
import com.polyp.polypweb.api.dto.ApiComparisonHistoryItemResponse;
import com.polyp.polypweb.api.dto.ApiPagedResponse;
import com.polyp.polypweb.api.error.ApiValidationException;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.ModelComparisonException;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.view.ComparisonResultView;
import org.springframework.http.CacheControl;
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

import com.polyp.polypweb.view.filter.ComparisonHistoryFilter;

import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/comparisons")
public class ApiComparisonController {

    private final ModelComparisonService comparisonService;

    public ApiComparisonController(ModelComparisonService comparisonService) {
        this.comparisonService = comparisonService;
    }

    @PostMapping(
            consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<ApiComparisonResponse> create(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @RequestParam(value = "image", required = false) MultipartFile image) {
        ApiComparisonResponse response = ApiComparisonResponse.from(
                comparisonService.compare(image, principal.getUserId())
        );
        return ResponseEntity.status(HttpStatus.CREATED)
                .cacheControl(CacheControl.noStore())
                .body(response);
    }

    @GetMapping(produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiPagedResponse<ApiComparisonHistoryItemResponse>> history(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @ModelAttribute ComparisonHistoryFilter filter) {
        filter.normalize();
        validateDates(filter.hasInvalidDateFormat(), filter.hasInvalidDateRange());
        var page = comparisonService.findHistoryPage(principal.getUserId(), filter)
                .map(ApiComparisonHistoryItemResponse::from);
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(ApiPagedResponse.from(page));
    }

    @GetMapping(value = "/{comparisonGroupId}", produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiComparisonResponse> detail(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String comparisonGroupId) {
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(ApiComparisonResponse.from(require(comparisonGroupId, principal)));
    }

    @GetMapping(
            value = "/{comparisonGroupId}/metadata",
            produces = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<ApiComparisonMetadataResponse> metadata(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String comparisonGroupId) {
        ApiComparisonResponse comparison = ApiComparisonResponse.from(
                require(comparisonGroupId, principal)
        );
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(ApiComparisonMetadataResponse.from(comparison));
    }

    @DeleteMapping("/{comparisonGroupId}")
    public ResponseEntity<Void> delete(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String comparisonGroupId) {
        boolean deleted = comparisonService.deleteForUser(
                comparisonGroupId,
                principal.getUserId(),
                principal.isAdmin()
        );
        if (!deleted) {
            throw new ModelComparisonException(
                    HttpStatus.NOT_FOUND,
                    "RESOURCE_NOT_FOUND",
                    "Không tìm thấy phiên so sánh."
            );
        }
        return ResponseEntity.noContent()
                .cacheControl(CacheControl.noStore())
                .build();
    }

    private ComparisonResultView require(
            String comparisonGroupId,
            CurrentUserPrincipal principal) {
        return comparisonService.requireForUser(
                comparisonGroupId,
                principal.getUserId(),
                principal.isAdmin()
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
