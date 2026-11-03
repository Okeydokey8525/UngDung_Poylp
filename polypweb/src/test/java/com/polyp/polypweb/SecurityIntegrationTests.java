package com.polyp.polypweb;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.config.AdminSeedRunner;
import com.polyp.polypweb.config.DiagnosisHistoryIndexInitializer;
import com.polyp.polypweb.config.UserAccountIndexInitializer;
import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.UserAccountRepository;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DashboardService;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.FileStorageService;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.view.AdminDashboardView;
import com.polyp.polypweb.view.AiHealthView;
import com.polyp.polypweb.view.ComparisonResultView;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.UserDashboardView;
import com.polyp.polypweb.view.filter.HistoryFilter;
import jakarta.servlet.http.HttpSession;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.mongodb.health.MongoHealthIndicator;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.matchesPattern;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.forwardedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.model;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.view;

@SpringBootTest
@AutoConfigureMockMvc
class SecurityIntegrationTests {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @MockitoBean
    private UserAccountRepository userAccountRepository;
    @MockitoBean
    private DiagnosisHistoryRepository diagnosisHistoryRepository;
    @MockitoBean
    private DiagnosisHistoryService diagnosisHistoryService;
    @MockitoBean
    private ModelComparisonService modelComparisonService;
    @MockitoBean
    private FileStorageService fileStorageService;
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

    private UserAccount enabledUser;
    private UserAccount enabledAdmin;
    private UserAccount disabledUser;

    @BeforeEach
    void setUp() {
        enabledUser = account("user-id", "user@example.com", UserRole.USER, true);
        enabledAdmin = account("admin-id", "admin@example.com", UserRole.ADMIN, true);
        disabledUser = account("disabled-id", "disabled@example.com", UserRole.USER, false);
        when(userAccountRepository.findByEmailIgnoreCase("user@example.com"))
                .thenReturn(Optional.of(enabledUser));
        when(userAccountRepository.findByEmailIgnoreCase("admin@example.com"))
                .thenReturn(Optional.of(enabledAdmin));
        when(userAccountRepository.findByEmailIgnoreCase("disabled@example.com"))
                .thenReturn(Optional.of(disabledUser));
        when(userAccountRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of());
        when(diagnosisHistoryService.findHistoryPage(anyString(), any())).thenReturn(Page.empty());
        when(modelComparisonService.findHistoryPage(anyString(), any())).thenReturn(Page.empty());
        when(dashboardService.userDashboard("user-id", "Regular User"))
                .thenReturn(emptyUserDashboard());
        when(dashboardService.adminDashboard()).thenReturn(emptyAdminDashboard());
        when(aiInferenceClient.serviceStatus())
                .thenReturn(new com.polyp.polypweb.client.AiServiceStatus(true, true));
        when(mongoHealthIndicator.health()).thenReturn(Health.up().build());
    }

    @Test
    void publicHomeLoginRegisterAndAboutAreOpen() throws Exception {
        mockMvc.perform(get("/")).andExpect(status().isOk());
        mockMvc.perform(get("/login")).andExpect(status().isOk());
        mockMvc.perform(get("/register")).andExpect(status().isOk());
        mockMvc.perform(get("/about")).andExpect(status().isOk());
    }

    @Test
    void privacyTermsAndDisclaimerArePublic() throws Exception {
        mockMvc.perform(get("/privacy"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("Chính sách quyền riêng tư")));
        mockMvc.perform(get("/terms"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("Điều khoản sử dụng")));
        mockMvc.perform(get("/disclaimer"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("không phải thiết bị y tế")));
    }

    @Test
    void footerAndRegisterLinkToLegalPages() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("href=\"/privacy\"")))
                .andExpect(content().string(containsString("href=\"/terms\"")))
                .andExpect(content().string(containsString("href=\"/disclaimer\"")));
        mockMvc.perform(get("/register"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("href=\"/privacy\"")))
                .andExpect(content().string(containsString("href=\"/terms\"")));
    }

    @Test
    void registerRendersPersistentFieldFeedbackAndAccessibleRelationships() throws Exception {
        mockMvc.perform(get("/register"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("id=\"fullNameError\"")))
                .andExpect(content().string(containsString("id=\"emailError\"")))
                .andExpect(content().string(containsString("id=\"passwordError\"")))
                .andExpect(content().string(containsString("id=\"confirmPasswordError\"")))
                .andExpect(content().string(containsString("id=\"acceptedTermsError\"")))
                .andExpect(content().string(containsString(
                        "aria-describedby=\"passwordHelp passwordError\""
                )))
                .andExpect(content().string(containsString("aria-invalid=\"false\"")))
                .andExpect(content().string(containsString(
                        "pattern=\"(?=.*[A-Za-z])(?=.*\\d).{8,72}\""
                )))
                .andExpect(content().string(containsString("Vui lòng nhập mật khẩu.")));
    }

    @Test
    void registerBlankSubmissionRendersFieldSpecificServerErrors() throws Exception {
        mockMvc.perform(post("/register").with(csrf()))
                .andExpect(status().isOk())
                .andExpect(view().name("auth/register"))
                .andExpect(model().attributeHasFieldErrors(
                        "registerForm",
                        "fullName",
                        "email",
                        "password",
                        "confirmPassword",
                        "acceptedTerms"
                ))
                .andExpect(content().string(containsString("Vui lòng nhập họ và tên.")))
                .andExpect(content().string(containsString("Vui lòng nhập email.")))
                .andExpect(content().string(containsString("Vui lòng nhập mật khẩu.")))
                .andExpect(content().string(containsString("Vui lòng xác nhận mật khẩu.")))
                .andExpect(content().string(containsString(
                        "Bạn cần đồng ý với điều khoản sử dụng."
                )))
                .andExpect(content().string(containsString("aria-invalid=\"true\"")));
    }

    @Test
    void registerRendersActualNameEmailAndPasswordRuleErrors() throws Exception {
        mockMvc.perform(post("/register")
                        .with(csrf())
                        .param("fullName", "A")
                        .param("email", "not-an-email")
                        .param("password", "password")
                        .param("confirmPassword", "password")
                        .param("acceptedTerms", "true"))
                .andExpect(status().isOk())
                .andExpect(model().attributeHasFieldErrors(
                        "registerForm",
                        "fullName",
                        "email",
                        "password"
                ))
                .andExpect(content().string(containsString(
                        "Họ và tên phải có từ 2 đến 100 ký tự."
                )))
                .andExpect(content().string(containsString("Địa chỉ email không hợp lệ.")))
                .andExpect(content().string(containsString(
                        "Mật khẩu phải có 8–72 ký tự, gồm ít nhất một chữ và một số."
                )))
                .andExpect(content().string(not(containsString("value=\"password\""))));
    }

    @Test
    void registerPasswordMismatchRendersErrorAtConfirmationField() throws Exception {
        mockMvc.perform(post("/register")
                        .with(csrf())
                        .param("fullName", "New User")
                        .param("email", "new@example.com")
                        .param("password", "Password123")
                        .param("confirmPassword", "Different123")
                        .param("acceptedTerms", "true"))
                .andExpect(status().isOk())
                .andExpect(model().attributeHasFieldErrors("registerForm", "confirmPassword"))
                .andExpect(content().string(containsString("Mật khẩu xác nhận chưa khớp.")))
                .andExpect(content().string(containsString("id=\"confirmPasswordError\"")));
    }

    @Test
    void registerDuplicateEmailRendersErrorAtEmailField() throws Exception {
        when(userAccountRepository.existsByEmailIgnoreCase("existing@example.com")).thenReturn(true);

        mockMvc.perform(post("/register")
                        .with(csrf())
                        .param("fullName", "Existing User")
                        .param("email", "existing@example.com")
                        .param("password", "Password123")
                        .param("confirmPassword", "Password123")
                        .param("acceptedTerms", "true"))
                .andExpect(status().isOk())
                .andExpect(model().attributeHasFieldErrors("registerForm", "email"))
                .andExpect(content().string(containsString("Email đã được sử dụng.")))
                .andExpect(content().string(containsString("id=\"emailError\"")));
    }

    @Test
    void publicPagesHaveSecurityAndCorrelationHeaders() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().string("X-Frame-Options", "DENY"))
                .andExpect(header().string("Referrer-Policy", "strict-origin-when-cross-origin"))
                .andExpect(header().exists("Permissions-Policy"))
                .andExpect(header().string(
                        "Content-Security-Policy",
                        containsString("default-src 'self'")
                ))
                .andExpect(header().exists("X-Request-ID"))
                .andExpect(header().doesNotExist("Strict-Transport-Security"));
    }

    @Test
    void actuatorHealthIsPublicButGuestDetailsAreHidden() throws Exception {
        mockMvc.perform(get("/actuator/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.components").doesNotExist())
                .andExpect(content().string(not(containsString("mongodb://"))))
                .andExpect(content().string(not(containsString("checkpoint"))));
    }

    @Test
    void adminCanSeeSafeHealthComponentsWithoutSecrets() throws Exception {
        mockMvc.perform(get("/actuator/health")
                        .with(user(principal(enabledAdmin))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.components.aiService.status").value("UP"))
                .andExpect(jsonPath("$.components.storage.status").value("UP"))
                .andExpect(jsonPath("$.components.mongo.status").value("UP"))
                .andExpect(content().string(not(containsString("mongodb://"))))
                .andExpect(content().string(not(containsString("best.pt"))));
    }

    @Test
    void dangerousActuatorEndpointsAreNotExposed() throws Exception {
        mockMvc.perform(get("/actuator/env").with(user(principal(enabledAdmin))))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/actuator/beans").with(user(principal(enabledAdmin))))
                .andExpect(status().isNotFound());
    }

    @Test
    void missingPageDoesNotExposeStackTrace() throws Exception {
        mockMvc.perform(get("/page-that-does-not-exist")
                        .with(user(principal(enabledUser))))
                .andExpect(status().isNotFound())
                .andExpect(content().string(not(containsString("java.lang"))))
                .andExpect(content().string(not(containsString("Exception"))))
                .andExpect(content().string(not(containsString("stacktrace"))));
    }

    @Test
    void loginAndRegisterHtmlContainRenderedCsrfTokens() throws Exception {
        mockMvc.perform(get("/login"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("name=\"_csrf\"")));
        mockMvc.perform(get("/register"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("name=\"_csrf\"")));
    }

    @Test
    void protectedDiagnosisRedirectsGuestToLogin() throws Exception {
        mockMvc.perform(get("/diagnose"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login"));
    }

    @Test
    void protectedHistoryRedirectsGuestToLogin() throws Exception {
        mockMvc.perform(get("/history"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login"));
    }

    @Test
    void protectedDashboardRedirectsGuestToLogin() throws Exception {
        mockMvc.perform(get("/dashboard"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login"));
    }

    @Test
    void userCanOpenOwnDashboard() throws Exception {
        mockMvc.perform(get("/dashboard").with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(view().name("dashboard"));

        verify(dashboardService).userDashboard("user-id", "Regular User");
    }

    @Test
    void userAccessingAdminReceives403Page() throws Exception {
        mockMvc.perform(get("/admin/users").with(user(principal(enabledUser))))
                .andExpect(status().isForbidden())
                .andExpect(forwardedUrl("/error/403"));
    }

    @Test
    void userAccessingAdminDashboardReceives403Page() throws Exception {
        mockMvc.perform(get("/admin/dashboard").with(user(principal(enabledUser))))
                .andExpect(status().isForbidden())
                .andExpect(forwardedUrl("/error/403"));
    }

    @Test
    void adminCanOpenDashboard() throws Exception {
        mockMvc.perform(get("/admin/dashboard").with(user(principal(enabledAdmin))))
                .andExpect(status().isOk())
                .andExpect(view().name("admin/dashboard"));
    }

    @Test
    void adminCanOpenBasicUserAdministration() throws Exception {
        mockMvc.perform(get("/admin/users").with(user(principal(enabledAdmin))))
                .andExpect(status().isOk())
                .andExpect(view().name("admin/users"));
    }

    @Test
    void disabledUserCannotLogin() throws Exception {
        mockMvc.perform(post("/login")
                        .with(csrf())
                        .param("email", "disabled@example.com")
                        .param("password", "Password123"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login?error"));
    }

    @Test
    void validUserCanLoginAndLogoutEndsSession() throws Exception {
        HttpSession session = (HttpSession) mockMvc.perform(post("/login")
                        .with(csrf())
                        .param("email", "user@example.com")
                        .param("password", "Password123"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/"))
                .andReturn()
                .getRequest()
                .getSession(false);

        mockMvc.perform(post("/logout").session((org.springframework.mock.web.MockHttpSession) session)
                        .with(csrf()))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login?logout"));
    }

    @Test
    void diagnosisDeleteWithoutCsrfIsRejected() throws Exception {
        mockMvc.perform(post("/history/diagnosis-id/delete").with(user(principal(enabledUser))))
                .andExpect(status().isForbidden());
    }

    @Test
    void comparisonDeleteWithoutCsrfIsRejected() throws Exception {
        mockMvc.perform(post("/comparisons/group-id/delete").with(user(principal(enabledUser))))
                .andExpect(status().isForbidden());
    }

    @Test
    void profileUpdateWithoutCsrfIsRejected() throws Exception {
        mockMvc.perform(post("/profile")
                        .with(user(principal(enabledUser)))
                        .param("fullName", "New Name")
                        .param("email", "new@example.com"))
                .andExpect(status().isForbidden());
    }

    @Test
    void historyUsesOnlyCurrentPrincipalUserId() throws Exception {
        mockMvc.perform(get("/history").with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(view().name("history"));

        verify(diagnosisHistoryService).findHistoryPage(eq("user-id"), any());
    }

    @Test
    void comparisonHistoryUsesOnlyCurrentPrincipalUserId() throws Exception {
        mockMvc.perform(get("/comparisons").with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(view().name("comparison-history"));

        verify(modelComparisonService).findHistoryPage(eq("user-id"), any());
    }

    @Test
    void invalidHistoryQueryParametersRenderSafelyAndNormalizeBeforeService() throws Exception {
        mockMvc.perform(get("/history")
                        .with(user(principal(enabledUser)))
                        .param("page", "-4")
                        .param("size", "999")
                        .param("model", "$where")
                        .param("sort", "userId")
                        .param("dateFrom", "not-a-date"))
                .andExpect(status().isOk())
                .andExpect(view().name("history"))
                .andExpect(content().string(containsString("Một số bộ lọc đã được điều chỉnh")));

        ArgumentCaptor<HistoryFilter> captor = ArgumentCaptor.forClass(HistoryFilter.class);
        verify(diagnosisHistoryService).findHistoryPage(eq("user-id"), captor.capture());
        assertEquals(0, captor.getValue().getPageIndex());
        assertEquals(10, captor.getValue().getPageSize());
    }

    @Test
    void historyPaginationRendersCurrentRangeAndPreservesFilters() throws Exception {
        DiagnosisResultView item = resultView(
                "diagnosis-a",
                "YOLO26s-seg",
                null,
                LocalDateTime.now()
        );
        when(diagnosisHistoryService.findHistoryPage(eq("user-id"), any()))
                .thenReturn(new PageImpl<>(
                        List.of(item),
                        PageRequest.of(1, 10),
                        21
                ));

        mockMvc.perform(get("/history")
                        .with(user(principal(enabledUser)))
                        .param("page", "1")
                        .param("size", "10")
                        .param("keyword", "kvasir")
                        .param("model", "YOLO26s-seg")
                        .param("detected", "true")
                        .param("sort", "oldest"))
                .andExpect(status().isOk())
                .andExpect(content().string(
                        containsString("Hiển thị 11–11 trong tổng số 21 kết quả")
                ))
                .andExpect(content().string(containsString("keyword=kvasir")))
                .andExpect(content().string(containsString("model=YOLO26s-seg")))
                .andExpect(content().string(containsString("sort=oldest")));
    }

    @Test
    void comparisonPaginationRendersOneGroupAndPreservesFilters() throws Exception {
        ComparisonResultView comparison = comparison(UUID.randomUUID().toString());
        when(modelComparisonService.findHistoryPage(eq("user-id"), any()))
                .thenReturn(new PageImpl<>(
                        List.of(comparison),
                        PageRequest.of(0, 10),
                        12
                ));

        mockMvc.perform(get("/comparisons")
                        .with(user(principal(enabledUser)))
                        .param("keyword", "case")
                        .param("baselineDetected", "true")
                        .param("vmambaDetected", "false")
                        .param("sort", "total-processing-desc"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("sample.jpg")))
                .andExpect(content().string(containsString("keyword=case")))
                .andExpect(content().string(containsString("baselineDetected=true")))
                .andExpect(content().string(containsString("vmambaDetected=false")));
    }

    @Test
    void ownerCanReadImageThroughDiagnosisEndpoint() throws Exception {
        DiagnosisHistory history = diagnosis("diagnosis-a", "user-id");
        when(diagnosisHistoryService.findDocumentAccessible("diagnosis-a", "user-id", false))
                .thenReturn(Optional.of(history));
        when(fileStorageService.loadMediaUrl(history.getOriginalImageUrl()))
                .thenReturn(Optional.of(new ByteArrayResource(new byte[]{1, 2, 3})));

        mockMvc.perform(get("/diagnoses/diagnosis-a/original-image")
                        .with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(content().bytes(new byte[]{1, 2, 3}));
    }

    @Test
    void userCannotReadAnotherUsersImage() throws Exception {
        when(diagnosisHistoryService.findDocumentAccessible("diagnosis-b", "user-id", false))
                .thenThrow(new org.springframework.security.access.AccessDeniedException("forbidden"));

        mockMvc.perform(get("/diagnoses/diagnosis-b/original-image")
                        .with(user(principal(enabledUser))))
                .andExpect(status().isForbidden());
    }

    @Test
    void downloadRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/diagnoses/diagnosis-a/download/original"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login"));
    }

    @Test
    void metadataRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/diagnoses/diagnosis-a/metadata.json"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login"));
    }

    @Test
    void ownerDownloadsOriginalAsAttachmentWithSafeNameAndContentType() throws Exception {
        DiagnosisHistory history = diagnosis("diagnosis-a", "user-id");
        when(diagnosisHistoryService.findDocumentAccessible("diagnosis-a", "user-id", false))
                .thenReturn(Optional.of(history));
        when(fileStorageService.loadMediaUrl(history.getOriginalImageUrl()))
                .thenReturn(Optional.of(new ByteArrayResource(new byte[]{4, 5, 6})));

        mockMvc.perform(get("/diagnoses/diagnosis-a/download/original")
                        .with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_JPEG))
                .andExpect(content().bytes(new byte[]{4, 5, 6}))
                .andExpect(header().string(
                        HttpHeaders.CONTENT_DISPOSITION,
                        containsString("attachment")
                ))
                .andExpect(header().string(
                        HttpHeaders.CONTENT_DISPOSITION,
                        containsString("polypvision_yolo26s-seg_diagnosis-a_original.jpg")
                ))
                .andExpect(header().string(
                        HttpHeaders.CONTENT_DISPOSITION,
                        not(containsString("sample.jpg"))
                ));
    }

    @Test
    void ownerDownloadsResultAsAttachment() throws Exception {
        DiagnosisHistory history = diagnosis("diagnosis-a", "user-id");
        when(diagnosisHistoryService.findDocumentAccessible("diagnosis-a", "user-id", false))
                .thenReturn(Optional.of(history));
        when(fileStorageService.loadMediaUrl(history.getResultImageUrl()))
                .thenReturn(Optional.of(new ByteArrayResource(new byte[]{7, 8})));

        mockMvc.perform(get("/diagnoses/diagnosis-a/download/result")
                        .with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_JPEG))
                .andExpect(header().string(
                        HttpHeaders.CONTENT_DISPOSITION,
                        containsString("attachment")
                ));
    }

    @Test
    void missingOrTraversalStorageFileReturns404() throws Exception {
        DiagnosisHistory history = diagnosis("diagnosis-a", "user-id");
        history.setOriginalImageUrl("/media/original/../../secret.txt");
        when(diagnosisHistoryService.findDocumentAccessible("diagnosis-a", "user-id", false))
                .thenReturn(Optional.of(history));
        when(fileStorageService.loadMediaUrl(history.getOriginalImageUrl()))
                .thenReturn(Optional.empty());

        mockMvc.perform(get("/diagnoses/diagnosis-a/download/original")
                        .with(user(principal(enabledUser))))
                .andExpect(status().isNotFound());
    }

    @Test
    void anotherUserCannotDownloadBySupplyingDiagnosisId() throws Exception {
        when(diagnosisHistoryService.findDocumentAccessible("diagnosis-b", "user-id", false))
                .thenThrow(new org.springframework.security.access.AccessDeniedException("forbidden"));

        mockMvc.perform(get("/diagnoses/diagnosis-b/download/result")
                        .with(user(principal(enabledUser)))
                        .param("userId", "owner-b"))
                .andExpect(status().isForbidden());
    }

    @Test
    void diagnosisMetadataContainsOnlyExportFieldsAndUsesConfidenceRatio() throws Exception {
        DiagnosisHistory history = diagnosis("diagnosis-a", "user-id");
        when(diagnosisHistoryService.findDocumentAccessible("diagnosis-a", "user-id", false))
                .thenReturn(Optional.of(history));

        mockMvc.perform(get("/diagnoses/diagnosis-a/metadata.json")
                        .with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(header().string(
                        HttpHeaders.CONTENT_DISPOSITION,
                        containsString("attachment")
                ))
                .andExpect(jsonPath("$.id").value("diagnosis-a"))
                .andExpect(jsonPath("$.modelCategory").value("BASELINE"))
                .andExpect(jsonPath("$.confidence").value(0.9))
                .andExpect(jsonPath("$.userId").doesNotExist())
                .andExpect(jsonPath("$.originalImageUrl").doesNotExist())
                .andExpect(jsonPath("$.resultImageUrl").doesNotExist())
                .andExpect(content().string(not(containsString("/media/"))));
    }

    @Test
    void comparisonMetadataContainsBaselineAndVmambaWithoutWinner() throws Exception {
        String groupId = UUID.randomUUID().toString();
        ComparisonResultView comparison = comparison(groupId);
        when(modelComparisonService.findForUser(groupId, "user-id", false))
                .thenReturn(Optional.of(comparison));

        mockMvc.perform(get("/comparisons/{id}/metadata.json", groupId)
                        .with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.comparisonGroupId").value(groupId))
                .andExpect(jsonPath("$.baseline.modelCategory").value("BASELINE"))
                .andExpect(jsonPath("$.vmamba.modelCategory").value("VMAMBA"))
                .andExpect(jsonPath("$.winner").doesNotExist())
                .andExpect(jsonPath("$.recommendedModel").doesNotExist())
                .andExpect(content().string(not(containsString("userId"))))
                .andExpect(content().string(not(containsString("/media/"))));
    }

    @Test
    void missingDiagnosisMetadataReturns404() throws Exception {
        when(diagnosisHistoryService.findDocumentAccessible("missing", "user-id", false))
                .thenReturn(Optional.empty());

        mockMvc.perform(get("/diagnoses/missing/metadata.json")
                        .with(user(principal(enabledUser))))
                .andExpect(status().isNotFound());
    }

    @Test
    void anotherUserCannotExportComparisonMetadata() throws Exception {
        String groupId = UUID.randomUUID().toString();
        when(modelComparisonService.findForUser(groupId, "user-id", false))
                .thenThrow(new org.springframework.security.access.AccessDeniedException("forbidden"));

        mockMvc.perform(get("/comparisons/{id}/metadata.json", groupId)
                        .with(user(principal(enabledUser))))
                .andExpect(status().isForbidden());
    }

    private CurrentUserPrincipal principal(UserAccount account) {
        return new CurrentUserPrincipal(account);
    }

    private UserAccount account(
            String id,
            String email,
            UserRole role,
            boolean enabled) {
        UserAccount account = new UserAccount();
        account.setId(id);
        account.setFullName(role == UserRole.ADMIN ? "Admin User" : "Regular User");
        account.setEmail(email);
        account.setPasswordHash(passwordEncoder.encode("Password123"));
        account.setRole(role);
        account.setEnabled(enabled);
        account.setCreatedAt(LocalDateTime.now());
        account.setUpdatedAt(LocalDateTime.now());
        return account;
    }

    private DiagnosisHistory diagnosis(String id, String ownerId) {
        DiagnosisHistory history = new DiagnosisHistory(
                ownerId,
                "sample.jpg",
                "YOLO26s-seg",
                true,
                "polyp",
                90,
                100,
                1,
                "/media/original/11111111-1111-1111-1111-111111111111.jpg",
                "/media/results/11111111-1111-1111-1111-111111111111_result.jpg",
                LocalDateTime.now(),
                null,
                false
        );
        history.setId(id);
        return history;
    }

    private ComparisonResultView comparison(String groupId) {
        LocalDateTime createdAt = LocalDateTime.now();
        DiagnosisResultView baseline = resultView(
                "baseline-id",
                "YOLO26s-seg",
                groupId,
                createdAt
        );
        DiagnosisResultView vmamba = resultView(
                "vmamba-id",
                "YOLO26s-TSVM-FP32-seg",
                groupId,
                createdAt
        );
        return new ComparisonResultView(
                groupId,
                baseline,
                vmamba,
                baseline.getOriginalImageUrl(),
                "sample.jpg",
                createdAt
        );
    }

    private DiagnosisResultView resultView(
            String id,
            String model,
            String groupId,
            LocalDateTime createdAt) {
        return new DiagnosisResultView(
                id,
                "/diagnoses/" + id + "/original-image",
                "/diagnoses/" + id + "/result-image",
                "sample.jpg",
                model,
                true,
                "polyp",
                90,
                100,
                1,
                "1280 × 720 px",
                createdAt,
                true,
                groupId,
                true
        );
    }

    @Test
    void tsvmResultRendersVmambaBadgeAndActualImageSize() throws Exception {
        when(diagnosisHistoryService.findByIdAccessible("display-test", "user-id", false))
                .thenReturn(Optional.of(displayRegressionResult("YOLO26s-TSVM-FP32-seg")));

        mockMvc.perform(get("/diagnoses/display-test").with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(model().attribute("vmambaModel", true))
                .andExpect(content().string(matchesPattern("(?s).*class=\"model-family-badge\\s+vmamba\">VMamba</span>.*")))
                .andExpect(content().string(containsString("621 × 530 px")));
    }

    @Test
    void baselineResultRendersBaselineBadge() throws Exception {
        when(diagnosisHistoryService.findByIdAccessible("display-test", "user-id", false))
                .thenReturn(Optional.of(displayRegressionResult("YOLO26s-seg")));

        mockMvc.perform(get("/diagnoses/display-test").with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(model().attribute("vmambaModel", false))
                .andExpect(content().string(matchesPattern("(?s).*class=\"model-family-badge\\s+baseline\">Baseline</span>.*")));
    }

    @Test
    void oldUnknownModelIsNotMislabelledAsBaseline() throws Exception {
        when(diagnosisHistoryService.findByIdAccessible("display-test", "user-id", false))
                .thenReturn(Optional.of(displayRegressionResult("historical-model")));

        mockMvc.perform(get("/diagnoses/display-test").with(user(principal(enabledUser))))
                .andExpect(status().isOk())
                .andExpect(model().attribute("unknownModel", true))
                .andExpect(content().string(containsString("Mô hình cũ")));
    }

    @Test
    void homeNamesComeFromCurrentSmallModelRegistry() throws Exception {
        mockMvc.perform(get("/"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("YOLO26s-seg và YOLO26s-TSVM-FP32-seg")))
                .andExpect(content().string(not(containsString("YOLO26n"))))
                .andExpect(content().string(containsString("đăng nhập để phân tích ảnh")));
    }

    private DiagnosisResultView displayRegressionResult(String modelType) {
        return new DiagnosisResultView(
                "display-test", "/diagnoses/display-test/original-image", "/diagnoses/display-test/result-image",
                "sample.jpg", modelType, true, "polyp", 60, 100, 2,
                "621 × 530 px", LocalDateTime.now(), true, null, false);
    }

    private UserDashboardView emptyUserDashboard() {
        return new UserDashboardView(
                "Regular User",
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0,
                "Chưa có dữ liệu",
                List.of(),
                List.of()
        );
    }

    private AdminDashboardView emptyAdminDashboard() {
        return new AdminDashboardView(
                0, 0, 0, 0, 0,
                0, 0, 0, 0, 0,
                0, 0, 0, 0, 0,
                List.of(),
                List.of(),
                List.of(),
                new AiHealthView(false, "Không khả dụng", "Không xác định", List.of())
        );
    }
}
