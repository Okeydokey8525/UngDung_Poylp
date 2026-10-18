package com.polyp.polypweb;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.config.AdminSeedRunner;
import com.polyp.polypweb.config.DiagnosisHistoryIndexInitializer;
import com.polyp.polypweb.config.UserAccountIndexInitializer;
import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.UserAccountRepository;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DashboardService;
import com.polyp.polypweb.service.DiagnosisAnalysisService;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.FileStorageService;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.view.DiagnosisResultView;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.mongodb.health.MongoHealthIndicator;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import com.polyp.polypweb.view.filter.HistoryFilter;
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
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class ApiDiagnosisIntegrationTests {

    @Autowired
    private MockMvc mockMvc;

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
    private ModelComparisonService modelComparisonService;
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
    private DiagnosisResultView result;
    private DiagnosisHistory history;

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
        result = result("diagnosis-1", "YOLO26s-seg");
        history = history("diagnosis-1", "user-id", false);
        when(mongoHealthIndicator.health()).thenReturn(Health.up().build());
    }

    @Test
    void guestCreateReturnsJson401() throws Exception {
        mockMvc.perform(multipart("/api/v1/diagnoses")
                        .file("image", new byte[]{1})
                        .param("modelType", "YOLO26s-seg")
                        .with(csrf()))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void guestHistoryReturnsJson401() throws Exception {
        mockMvc.perform(get("/api/v1/diagnoses"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void diagnosisHistoryReturnsSafePagedContractForCurrentUser() throws Exception {
        when(historyService.findHistoryPage(eq("user-id"), any(HistoryFilter.class)))
                .thenReturn(new PageImpl<>(List.of(result), PageRequest.of(0, 10), 21));

        mockMvc.perform(get("/api/v1/diagnoses").with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.items[0].id").value("diagnosis-1"))
                .andExpect(jsonPath("$.items[0].confidence").value(0.624))
                .andExpect(jsonPath("$.page").value(0))
                .andExpect(jsonPath("$.size").value(10))
                .andExpect(jsonPath("$.totalItems").value(21))
                .andExpect(jsonPath("$.totalPages").value(3))
                .andExpect(jsonPath("$.hasNext").value(true))
                .andExpect(content().string(not(containsString("userId"))))
                .andExpect(content().string(not(containsString("/media/"))));
    }

    @Test
    void diagnosisHistoryNormalizesPageSizeAndPassesFiltersServerSide() throws Exception {
        when(historyService.findHistoryPage(eq("user-id"), any(HistoryFilter.class)))
                .thenReturn(new PageImpl<>(List.of(), PageRequest.of(0, 10), 0));

        mockMvc.perform(get("/api/v1/diagnoses")
                        .param("page", "-7")
                        .param("size", "999")
                        .param("keyword", "  sample  ")
                        .param("model", "YOLO26s-seg")
                        .param("detected", "true")
                        .param("sort", "processing-desc")
                        .with(user(principal)))
                .andExpect(status().isOk());

        ArgumentCaptor<HistoryFilter> captor = ArgumentCaptor.forClass(HistoryFilter.class);
        verify(historyService).findHistoryPage(eq("user-id"), captor.capture());
        HistoryFilter filter = captor.getValue();
        org.junit.jupiter.api.Assertions.assertEquals(0, filter.getPageIndex());
        org.junit.jupiter.api.Assertions.assertEquals(10, filter.getPageSize());
        org.junit.jupiter.api.Assertions.assertEquals("sample", filter.getKeyword());
        org.junit.jupiter.api.Assertions.assertEquals("YOLO26s-seg", filter.getModel());
        org.junit.jupiter.api.Assertions.assertEquals("true", filter.getDetected());
        org.junit.jupiter.api.Assertions.assertEquals("processing-desc", filter.getSort());
    }

    @Test
    void diagnosisHistoryRejectsInvalidDateRange() throws Exception {
        mockMvc.perform(get("/api/v1/diagnoses")
                        .param("dateFrom", "2026-08-02")
                        .param("dateTo", "2026-08-01")
                        .with(user(principal)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.fieldErrors.dateRange").exists());
    }

    @Test
    void diagnosisHistoryRejectsInvalidDateFormat() throws Exception {
        mockMvc.perform(get("/api/v1/diagnoses")
                        .param("dateFrom", "01-08-2026")
                        .with(user(principal)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void createWithoutCsrfReturns403() throws Exception {
        mockMvc.perform(multipart("/api/v1/diagnoses")
                        .file("image", new byte[]{1})
                        .param("modelType", "YOLO26s-seg")
                        .with(user(principal)))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void validBaselineCreateReturns201AndSafeContract() throws Exception {
        when(analysisService.analyze(any(), eq("YOLO26s-seg"), eq("user-id")))
                .thenReturn(result);

        mockMvc.perform(createRequest("YOLO26s-seg"))
                .andExpect(status().isCreated())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.id").value("diagnosis-1"))
                .andExpect(jsonPath("$.modelType").value("YOLO26s-seg"))
                .andExpect(jsonPath("$.modelCategory").value("BASELINE"))
                .andExpect(jsonPath("$.confidence").value(0.624))
                .andExpect(jsonPath("$.originalImageUrl")
                        .value("/api/v1/diagnoses/diagnosis-1/images/original"));
    }

    @Test
    void validVmambaCreateReturns201() throws Exception {
        when(analysisService.analyze(any(), eq("YOLO26s-TSVM-FP32-seg"), eq("user-id")))
                .thenReturn(result("diagnosis-2", "YOLO26s-TSVM-FP32-seg"));

        mockMvc.perform(createRequest("YOLO26s-TSVM-FP32-seg"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.modelCategory").value("VMAMBA"));
    }

    @Test
    void createAlwaysUsesPrincipalAndIgnoresSubmittedUserId() throws Exception {
        when(analysisService.analyze(any(), eq("YOLO26s-seg"), eq("user-id")))
                .thenReturn(result);

        mockMvc.perform(multipart("/api/v1/diagnoses")
                        .file("image", new byte[]{1})
                        .param("modelType", "YOLO26s-seg")
                        .param("userId", "attacker-id")
                        .with(user(principal))
                        .with(csrf()))
                .andExpect(status().isCreated());

        verify(analysisService).analyze(any(), eq("YOLO26s-seg"), eq("user-id"));
        verify(analysisService, never()).analyze(any(), anyString(), eq("attacker-id"));
    }

    @Test
    void createResponseNeverLeaksInternalFields() throws Exception {
        when(analysisService.analyze(any(), anyString(), anyString())).thenReturn(result);

        mockMvc.perform(createRequest("YOLO26s-seg"))
                .andExpect(status().isCreated())
                .andExpect(content().string(not(containsString("userId"))))
                .andExpect(content().string(not(containsString("/media/"))))
                .andExpect(content().string(not(containsString("checkpoint"))))
                .andExpect(content().string(not(containsString("resultImageBase64"))));
    }

    @Test
    void invalidModelReturns400() throws Exception {
        expectCreateFailure("INVALID_MODEL", 400, "YOLO26x-seg");
    }

    @Test
    void emptyFileReturns400() throws Exception {
        expectCreateFailure("EMPTY_FILE", 400, "YOLO26s-seg");
    }

    @Test
    void oversizedFileReturns413() throws Exception {
        expectCreateFailure("FILE_TOO_LARGE", 413, "YOLO26s-seg");
    }

    @Test
    void unsupportedMimeReturns415() throws Exception {
        expectCreateFailure("UNSUPPORTED_MEDIA_TYPE", 415, "YOLO26s-seg");
    }

    @Test
    void corruptImageReturns422() throws Exception {
        expectCreateFailure("INVALID_IMAGE", 422, "YOLO26s-seg");
    }

    @Test
    void aiUnavailableReturns503() throws Exception {
        expectCreateFailure("AI_SERVICE_UNAVAILABLE", 503, "YOLO26s-seg");
    }

    @Test
    void modelUnavailableReturns503() throws Exception {
        expectCreateFailure("MODEL_UNAVAILABLE", 503, "YOLO26s-seg");
    }

    @Test
    void aiTimeoutReturns504() throws Exception {
        expectCreateFailure("AI_SERVICE_TIMEOUT", 504, "YOLO26s-seg");
    }

    @Test
    void modelResponseMismatchReturns502() throws Exception {
        expectCreateFailure("MODEL_RESPONSE_MISMATCH", 502, "YOLO26s-seg");
    }

    @Test
    void ownerCanReadDetail() throws Exception {
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenReturn(Optional.of(history));
        when(historyService.toView(history)).thenReturn(result);

        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1").with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.fileName").value("sample.jpg"));
    }

    @Test
    void missingDetailReturns404Json() throws Exception {
        when(historyService.findDocumentAccessible("missing", "user-id", false))
                .thenReturn(Optional.empty());

        mockMvc.perform(get("/api/v1/diagnoses/missing").with(user(principal)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("RESOURCE_NOT_FOUND"));
    }

    @Test
    void otherUsersDetailIsForbidden() throws Exception {
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenThrow(new AccessDeniedException("denied"));

        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1").with(user(principal)))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("ACCESS_DENIED"));
    }

    @Test
    void ownerCanLoadOriginalAndResultInline() throws Exception {
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenReturn(Optional.of(history));
        when(storageService.loadMediaUrl("/media/original/file.jpg"))
                .thenReturn(Optional.of(new ByteArrayResource(new byte[]{1, 2, 3})));
        when(storageService.loadMediaUrl("/media/results/file_result.jpg"))
                .thenReturn(Optional.of(new ByteArrayResource(new byte[]{4, 5})));

        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1/images/original")
                        .header(HttpHeaders.ACCEPT, "image/*, application/json")
                        .with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_JPEG))
                .andExpect(header().string("Cache-Control", containsString("private")))
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().doesNotExist("Content-Disposition"))
                .andExpect(content().bytes(new byte[]{1, 2, 3}));
        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1/images/result")
                        .header(HttpHeaders.ACCEPT, "image/*, application/json")
                        .with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_JPEG))
                .andExpect(content().bytes(new byte[]{4, 5}));
    }

    @Test
    void pngImageReturnsRawBytesWithPngContentType() throws Exception {
        history.setOriginalImageUrl("/media/original/file.png");
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenReturn(Optional.of(history));
        when(storageService.loadMediaUrl("/media/original/file.png"))
                .thenReturn(Optional.of(new ByteArrayResource(new byte[]{9, 8, 7})));

        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1/images/original")
                        .header(HttpHeaders.ACCEPT, "image/*, application/json")
                        .with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_PNG))
                .andExpect(content().bytes(new byte[]{9, 8, 7}));
    }

    @Test
    void comparisonResultImagesRemainAccessibleToTheirOwner() throws Exception {
        DiagnosisHistory comparison = history("comparison-result", "user-id", true);
        when(historyService.findDocumentAccessible("comparison-result", "user-id", false))
                .thenReturn(Optional.of(comparison));
        when(storageService.loadMediaUrl("/media/results/file_result.jpg"))
                .thenReturn(Optional.of(new ByteArrayResource(new byte[]{6, 5, 4})));

        mockMvc.perform(get("/api/v1/diagnoses/comparison-result/images/result")
                        .header(HttpHeaders.ACCEPT, "image/*, application/json")
                        .with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_JPEG))
                .andExpect(content().bytes(new byte[]{6, 5, 4}));
    }

    @Test
    void imageRequestCanReceiveJson401() throws Exception {
        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1/images/original")
                        .header(HttpHeaders.ACCEPT, "image/*, application/json"))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void imageRequestCanReceiveJson403WithoutSecondary406() throws Exception {
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenThrow(new AccessDeniedException("denied"));

        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1/images/original")
                        .header(HttpHeaders.ACCEPT, "image/*, application/json")
                        .with(user(principal)))
                .andExpect(status().isForbidden())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value("ACCESS_DENIED"));
    }

    @Test
    void missingImageFileReturns404() throws Exception {
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenReturn(Optional.of(history));
        when(storageService.loadMediaUrl(anyString())).thenReturn(Optional.empty());

        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1/images/result")
                        .header(HttpHeaders.ACCEPT, "image/*, application/json")
                        .with(user(principal)))
                .andExpect(status().isNotFound())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value("FILE_NOT_FOUND"));
    }

    @Test
    void metadataIsInlineAndContainsNoInternalData() throws Exception {
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenReturn(Optional.of(history));
        when(historyService.toView(history)).thenReturn(result);

        mockMvc.perform(get("/api/v1/diagnoses/diagnosis-1/metadata")
                        .with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(header().doesNotExist("Content-Disposition"))
                .andExpect(jsonPath("$.modelCategory").value("BASELINE"))
                .andExpect(content().string(not(containsString("userId"))))
                .andExpect(content().string(not(containsString("ImageUrl"))))
                .andExpect(content().string(not(containsString("/media/"))));
    }

    @Test
    void deleteWithoutCsrfReturns403() throws Exception {
        mockMvc.perform(delete("/api/v1/diagnoses/diagnosis-1")
                        .with(user(principal)))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void ownerDeleteReturns204AndDelegatesFileCleanupService() throws Exception {
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenReturn(Optional.of(history));
        when(historyService.deleteAccessible("diagnosis-1", "user-id", false))
                .thenReturn(true);

        mockMvc.perform(delete("/api/v1/diagnoses/diagnosis-1")
                        .with(user(principal))
                        .with(csrf()))
                .andExpect(status().isNoContent());

        verify(historyService).deleteAccessible("diagnosis-1", "user-id", false);
    }

    @Test
    void otherUsersDeleteIsForbidden() throws Exception {
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenThrow(new AccessDeniedException("denied"));

        mockMvc.perform(delete("/api/v1/diagnoses/diagnosis-1")
                        .with(user(principal))
                        .with(csrf()))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("ACCESS_DENIED"));
    }

    @Test
    void comparisonResultCannotBeDeletedIndividually() throws Exception {
        DiagnosisHistory comparison = history("diagnosis-1", "user-id", true);
        when(historyService.findDocumentAccessible("diagnosis-1", "user-id", false))
                .thenReturn(Optional.of(comparison));

        mockMvc.perform(delete("/api/v1/diagnoses/diagnosis-1")
                        .with(user(principal))
                        .with(csrf()))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code")
                        .value("COMPARISON_RESULT_REQUIRES_GROUP_DELETE"));
        verify(historyService, never()).deleteAccessible(anyString(), anyString(), eq(false));
    }

    @Test
    void webDiagnosisStillRedirectsToSavedResult() throws Exception {
        when(analysisService.analyze(any(), eq("YOLO26s-seg"), eq("user-id")))
                .thenReturn(result);

        mockMvc.perform(multipart("/diagnose")
                        .file("image", new byte[]{1})
                        .param("modelType", "yolo26s-seg")
                        .with(user(principal))
                        .with(csrf()))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/diagnoses/diagnosis-1"));
    }

    private org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder createRequest(
            String modelType) {
        return multipart("/api/v1/diagnoses")
                .file("image", new byte[]{1})
                .param("modelType", modelType)
                .with(user(principal))
                .with(csrf());
    }

    private void expectCreateFailure(String code, int status, String modelType) throws Exception {
        when(analysisService.analyze(any(), eq(modelType), eq("user-id")))
                .thenThrow(new DiagnosisOperationException(
                        HttpStatusCode.status(status),
                        code,
                        "safe error"
                ));

        mockMvc.perform(createRequest(modelType))
                .andExpect(status().is(status))
                .andExpect(jsonPath("$.code").value(code))
                .andExpect(content().string(not(containsString("Exception"))));
    }

    private DiagnosisResultView result(String id, String modelType) {
        return new DiagnosisResultView(
                id,
                "/diagnoses/" + id + "/original-image",
                "/diagnoses/" + id + "/result-image",
                "sample.jpg",
                modelType,
                true,
                "polyp",
                62.4,
                148.5,
                2,
                "",
                LocalDateTime.of(2026, 8, 1, 9, 30),
                true,
                null,
                false
        );
    }

    private DiagnosisHistory history(String id, String userId, boolean comparison) {
        DiagnosisHistory value = new DiagnosisHistory(
                userId,
                "sample.jpg",
                "YOLO26s-seg",
                true,
                "polyp",
                62.4,
                148.5,
                2,
                "/media/original/file.jpg",
                "/media/results/file_result.jpg",
                LocalDateTime.of(2026, 8, 1, 9, 30),
                comparison ? "group-id" : null,
                comparison
        );
        value.setId(id);
        return value;
    }

    private static final class HttpStatusCode {
        private static org.springframework.http.HttpStatus status(int value) {
            return org.springframework.http.HttpStatus.valueOf(value);
        }
    }
}
