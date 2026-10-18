package com.polyp.polypweb;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.config.AdminSeedRunner;
import com.polyp.polypweb.config.DiagnosisHistoryIndexInitializer;
import com.polyp.polypweb.config.UserAccountIndexInitializer;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.UserAccountRepository;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DashboardService;
import com.polyp.polypweb.service.DiagnosisAnalysisService;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.FileStorageService;
import com.polyp.polypweb.service.ModelComparisonException;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.view.ComparisonResultView;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.filter.ComparisonHistoryFilter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.mongodb.health.MongoHealthIndicator;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;

import org.mockito.ArgumentCaptor;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class ApiComparisonIntegrationTests {

    private static final String GROUP_ID = "6c5e3cc3-e7e9-4c1d-a6a8-b0c1efcc66aa";

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private ModelComparisonService comparisonService;
    @MockitoBean
    private DiagnosisAnalysisService analysisService;
    @MockitoBean
    private DiagnosisHistoryService historyService;
    @MockitoBean
    private FileStorageService storageService;
    @MockitoBean
    private DiagnosisHistoryRepository diagnosisHistoryRepository;
    @MockitoBean
    private UserAccountRepository userAccountRepository;
    @MockitoBean
    private AiInferenceClient aiInferenceClient;
    @MockitoBean
    private DashboardService dashboardService;
    @MockitoBean
    private UserAccountIndexInitializer userAccountIndexInitializer;
    @MockitoBean
    private DiagnosisHistoryIndexInitializer diagnosisHistoryIndexInitializer;
    @MockitoBean
    private AdminSeedRunner adminSeedRunner;
    @MockitoBean
    private MongoHealthIndicator mongoHealthIndicator;

    private CurrentUserPrincipal principal;
    private ComparisonResultView comparison;

    @BeforeEach
    void setUp() {
        UserAccount account = new UserAccount();
        account.setId("user-id");
        account.setFullName("User A");
        account.setEmail("user@example.com");
        account.setPasswordHash("hash");
        account.setRole(UserRole.USER);
        account.setEnabled(true);
        principal = new CurrentUserPrincipal(account);
        comparison = comparison();
        when(mongoHealthIndicator.health()).thenReturn(Health.up().build());
    }

    @Test
    void guestCreateReturnsJson401() throws Exception {
        mockMvc.perform(multipart("/api/v1/comparisons")
                        .file("image", new byte[]{1})
                        .with(csrf()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void guestComparisonHistoryReturnsJson401() throws Exception {
        mockMvc.perform(get("/api/v1/comparisons"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void comparisonHistoryReturnsOneSafeItemPerGroup() throws Exception {
        when(comparisonService.findHistoryPage(eq("user-id"), any(ComparisonHistoryFilter.class)))
                .thenReturn(new PageImpl<>(List.of(comparison), PageRequest.of(0, 10), 12));

        mockMvc.perform(get("/api/v1/comparisons").with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.items.length()").value(1))
                .andExpect(jsonPath("$.items[0].comparisonGroupId").value(GROUP_ID))
                .andExpect(jsonPath("$.items[0].baseline.id").value("baseline-id"))
                .andExpect(jsonPath("$.items[0].vmamba.id").value("vmamba-id"))
                .andExpect(jsonPath("$.items[0].totalProcessingTimeMs").value(322.7))
                .andExpect(jsonPath("$.totalItems").value(12))
                .andExpect(jsonPath("$.totalPages").value(2))
                .andExpect(content().string(not(containsString("winner"))))
                .andExpect(content().string(not(containsString("userId"))))
                .andExpect(content().string(not(containsString("/media/"))));
    }

    @Test
    void comparisonHistoryPassesNormalizedFiltersForCurrentUser() throws Exception {
        when(comparisonService.findHistoryPage(eq("user-id"), any(ComparisonHistoryFilter.class)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(0, 10), 0));

        mockMvc.perform(get("/api/v1/comparisons")
                        .param("page", "-1")
                        .param("size", "7")
                        .param("keyword", "  case.*  ")
                        .param("baselineDetected", "true")
                        .param("vmambaDetected", "false")
                        .param("sort", "total-processing-desc")
                        .with(user(principal)))
                .andExpect(status().isOk());

        ArgumentCaptor<ComparisonHistoryFilter> captor =
                ArgumentCaptor.forClass(ComparisonHistoryFilter.class);
        verify(comparisonService).findHistoryPage(eq("user-id"), captor.capture());
        ComparisonHistoryFilter filter = captor.getValue();
        org.junit.jupiter.api.Assertions.assertEquals(0, filter.getPageIndex());
        org.junit.jupiter.api.Assertions.assertEquals(10, filter.getPageSize());
        org.junit.jupiter.api.Assertions.assertEquals("case.*", filter.getKeyword());
        org.junit.jupiter.api.Assertions.assertEquals("true", filter.getBaselineDetected());
        org.junit.jupiter.api.Assertions.assertEquals("false", filter.getVmambaDetected());
    }

    @Test
    void comparisonHistoryRejectsInvalidDates() throws Exception {
        mockMvc.perform(get("/api/v1/comparisons")
                        .param("dateFrom", "2026-08-02")
                        .param("dateTo", "2026-08-01")
                        .with(user(principal)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void createWithoutCsrfReturns403() throws Exception {
        mockMvc.perform(multipart("/api/v1/comparisons")
                        .file("image", new byte[]{1})
                        .with(user(principal)))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void validCreateReturns201WithBothModelsAndSequentialTotal() throws Exception {
        when(comparisonService.compare(any(), eq("user-id"))).thenReturn(comparison);

        mockMvc.perform(createRequest())
                .andExpect(status().isCreated())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.comparisonGroupId").value(GROUP_ID))
                .andExpect(jsonPath("$.baseline.modelType").value("YOLO26s-seg"))
                .andExpect(jsonPath("$.baseline.modelCategory").value("BASELINE"))
                .andExpect(jsonPath("$.vmamba.modelType").value("YOLO26s-TSVM-FP32-seg"))
                .andExpect(jsonPath("$.vmamba.modelCategory").value("VMAMBA"))
                .andExpect(jsonPath("$.totalProcessingTimeMs").value(322.7))
                .andExpect(jsonPath("$.originalImageUrl")
                        .value("/api/v1/diagnoses/baseline-id/images/original"))
                .andExpect(jsonPath("$.baseline.resultImageUrl")
                        .value("/api/v1/diagnoses/baseline-id/images/result"))
                .andExpect(jsonPath("$.vmamba.resultImageUrl")
                        .value("/api/v1/diagnoses/vmamba-id/images/result"));
    }

    @Test
    void responseNeverContainsWinnerOrInternalFields() throws Exception {
        when(comparisonService.compare(any(), anyString())).thenReturn(comparison);

        mockMvc.perform(createRequest())
                .andExpect(status().isCreated())
                .andExpect(content().string(not(containsString("winner"))))
                .andExpect(content().string(not(containsString("betterModel"))))
                .andExpect(content().string(not(containsString("userId"))))
                .andExpect(content().string(not(containsString("/media/"))))
                .andExpect(content().string(not(containsString("checkpoint"))));
    }

    @Test
    void submittedModelAndUserIdAreIgnored() throws Exception {
        when(comparisonService.compare(any(), eq("user-id"))).thenReturn(comparison);

        mockMvc.perform(multipart("/api/v1/comparisons")
                        .file("image", new byte[]{1})
                        .param("modelType", "attacker-model")
                        .param("userId", "attacker-id")
                        .with(user(principal))
                        .with(csrf()))
                .andExpect(status().isCreated());

        verify(comparisonService).compare(any(), eq("user-id"));
        verify(comparisonService, never()).compare(any(), eq("attacker-id"));
    }

    @Test void emptyFileReturns400() throws Exception { expectCreateFailure(400, "EMPTY_FILE"); }
    @Test void oversizedFileReturns413() throws Exception { expectCreateFailure(413, "FILE_TOO_LARGE"); }
    @Test void wrongMimeReturns415() throws Exception { expectCreateFailure(415, "UNSUPPORTED_MEDIA_TYPE"); }
    @Test void corruptImageReturns422() throws Exception { expectCreateFailure(422, "INVALID_IMAGE"); }
    @Test void baselineUnavailableReturns503() throws Exception { expectCreateFailure(503, "BASELINE_MODEL_UNAVAILABLE"); }
    @Test void vmambaUnavailableReturns503() throws Exception { expectCreateFailure(503, "VMAMBA_MODEL_UNAVAILABLE"); }
    @Test void baselineTimeoutReturns504() throws Exception { expectCreateFailure(504, "BASELINE_TIMEOUT"); }
    @Test void vmambaTimeoutReturns504() throws Exception { expectCreateFailure(504, "VMAMBA_TIMEOUT"); }
    @Test void modelMismatchReturns502() throws Exception { expectCreateFailure(502, "MODEL_RESPONSE_MISMATCH"); }

    @Test
    void ownerCanReadDetail() throws Exception {
        when(comparisonService.requireForUser(GROUP_ID, "user-id", false))
                .thenReturn(comparison);
        mockMvc.perform(get("/api/v1/comparisons/{id}", GROUP_ID).with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.fileName").value("sample.jpg"));
    }

    @Test
    void otherUserDetailIsForbidden() throws Exception {
        when(comparisonService.requireForUser(GROUP_ID, "user-id", false))
                .thenThrow(new AccessDeniedException("denied"));
        mockMvc.perform(get("/api/v1/comparisons/{id}", GROUP_ID).with(user(principal)))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("ACCESS_DENIED"));
    }

    @Test
    void missingGroupReturns404() throws Exception {
        expectDetailFailure(HttpStatus.NOT_FOUND, "RESOURCE_NOT_FOUND");
    }

    @Test
    void incompleteGroupReturns409() throws Exception {
        expectDetailFailure(HttpStatus.CONFLICT, "INCOMPLETE_COMPARISON");
    }

    @Test
    void metadataIsInlineAndSafe() throws Exception {
        when(comparisonService.requireForUser(GROUP_ID, "user-id", false))
                .thenReturn(comparison);
        mockMvc.perform(get("/api/v1/comparisons/{id}/metadata", GROUP_ID)
                        .with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(header().doesNotExist("Content-Disposition"))
                .andExpect(jsonPath("$.baseline.modelType").value("YOLO26s-seg"))
                .andExpect(content().string(not(containsString("winner"))))
                .andExpect(content().string(not(containsString("userId"))))
                .andExpect(content().string(not(containsString("/media/"))));
    }

    @Test
    void deleteWithoutCsrfReturns403() throws Exception {
        mockMvc.perform(delete("/api/v1/comparisons/{id}", GROUP_ID)
                        .with(user(principal)))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void ownerDeleteReturns204() throws Exception {
        when(comparisonService.deleteForUser(GROUP_ID, "user-id", false)).thenReturn(true);
        mockMvc.perform(delete("/api/v1/comparisons/{id}", GROUP_ID)
                        .with(user(principal)).with(csrf()))
                .andExpect(status().isNoContent());
        verify(comparisonService).deleteForUser(GROUP_ID, "user-id", false);
    }

    @Test
    void missingDeleteReturns404() throws Exception {
        when(comparisonService.deleteForUser(GROUP_ID, "user-id", false)).thenReturn(false);
        mockMvc.perform(delete("/api/v1/comparisons/{id}", GROUP_ID)
                        .with(user(principal)).with(csrf()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("RESOURCE_NOT_FOUND"));
    }

    @Test
    void otherUserDeleteIsForbidden() throws Exception {
        when(comparisonService.deleteForUser(GROUP_ID, "user-id", false))
                .thenThrow(new AccessDeniedException("denied"));
        mockMvc.perform(delete("/api/v1/comparisons/{id}", GROUP_ID)
                        .with(user(principal)).with(csrf()))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("ACCESS_DENIED"));
    }

    private org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder createRequest() {
        return multipart("/api/v1/comparisons")
                .file("image", new byte[]{1})
                .with(user(principal))
                .with(csrf());
    }

    private void expectCreateFailure(int status, String code) throws Exception {
        when(comparisonService.compare(any(), eq("user-id")))
                .thenThrow(new ModelComparisonException(
                        HttpStatus.valueOf(status), code, "safe error"));
        mockMvc.perform(createRequest())
                .andExpect(status().is(status))
                .andExpect(jsonPath("$.code").value(code))
                .andExpect(content().string(not(containsString("Exception"))));
    }

    private void expectDetailFailure(HttpStatus status, String code) throws Exception {
        when(comparisonService.requireForUser(GROUP_ID, "user-id", false))
                .thenThrow(new ModelComparisonException(status, code, "safe error"));
        mockMvc.perform(get("/api/v1/comparisons/{id}", GROUP_ID).with(user(principal)))
                .andExpect(status().is(status.value()))
                .andExpect(jsonPath("$.code").value(code));
    }

    private ComparisonResultView comparison() {
        LocalDateTime createdAt = LocalDateTime.of(2026, 8, 1, 10, 0);
        return new ComparisonResultView(
                GROUP_ID,
                result("baseline-id", "YOLO26s-seg", 62.4, 148.5, createdAt),
                result("vmamba-id", "YOLO26s-TSVM-FP32-seg", 67, 174.2, createdAt),
                "/media/original/shared.jpg",
                "sample.jpg",
                createdAt
        );
    }

    private DiagnosisResultView result(
            String id,
            String model,
            double confidence,
            double time,
            LocalDateTime createdAt) {
        return new DiagnosisResultView(
                id,
                "/media/original/shared.jpg",
                "/media/results/" + id + ".jpg",
                "sample.jpg",
                model,
                true,
                "polyp",
                confidence,
                time,
                2,
                "",
                createdAt,
                true,
                GROUP_ID,
                true
        );
    }
}
