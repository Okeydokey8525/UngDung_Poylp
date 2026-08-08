package com.polyp.polypweb.api;

import com.polyp.polypweb.api.dto.ApiDashboardResponse;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DashboardService;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping(value = "/api/v1", produces = MediaType.APPLICATION_JSON_VALUE)
public class ApiDashboardController {

    private final DashboardService dashboardService;

    public ApiDashboardController(DashboardService dashboardService) {
        this.dashboardService = dashboardService;
    }

    @GetMapping("/dashboard")
    public ResponseEntity<ApiDashboardResponse> dashboard(
            @AuthenticationPrincipal CurrentUserPrincipal principal) {
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(ApiDashboardResponse.from(
                        dashboardService.userDashboard(
                                principal.getUserId(),
                                principal.getFullName()
                        )
                ));
    }
}
