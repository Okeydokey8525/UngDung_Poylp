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
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.FileStorageService;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.view.DailyUsageView;
import com.polyp.polypweb.view.RecentActivityView;
import com.polyp.polypweb.view.UserDashboardView;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.mongodb.health.MongoHealthIndicator;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class ApiUserFeaturesIntegrationTests {

    private static final String OLD_PASSWORD = "OldPass123";
    private static final String NEW_PASSWORD = "NewPass456";

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

    private UserAccount account;
    private CurrentUserPrincipal principal;

    @BeforeEach
    void setUp() {
        account = account("user-id", "User A", "user@example.com", OLD_PASSWORD);
        principal = new CurrentUserPrincipal(account);
        when(userAccountRepository.findById("user-id")).thenReturn(Optional.of(account));
        when(userAccountRepository.findByEmailIgnoreCase(anyString())).thenAnswer(invocation -> {
            String email = invocation.getArgument(0);
            return email.equalsIgnoreCase(account.getEmail())
                    ? Optional.of(account)
                    : Optional.empty();
        });
        when(userAccountRepository.save(any(UserAccount.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        when(dashboardService.userDashboard(anyString(), anyString()))
                .thenReturn(emptyDashboard());
        when(mongoHealthIndicator.health()).thenReturn(Health.up().build());
    }

    @Test
    void guestDashboardReturnsJson401() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard"))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void userDashboardReturns200AndNoStore() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard").with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.summary.totalInferenceCount").value(0));
    }

    @Test
    void dashboardUsesOnlyCurrentPrincipalIdentity() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard").with(user(principal)))
                .andExpect(status().isOk());

        verify(dashboardService).userDashboard("user-id", "User A");
    }

    @Test
    void dashboardDoesNotExposeUserIdOrStoragePaths() throws Exception {
        when(dashboardService.userDashboard("user-id", "User A"))
                .thenReturn(populatedDashboard());

        mockMvc.perform(get("/api/v1/dashboard").with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("userId")
                )))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("/media/original")
                )))
                .andExpect(jsonPath("$.recentActivities[0].originalImageUrl")
                        .value("/diagnoses/diagnosis-1/original-image"));
    }

    @Test
    void emptyDashboardHasZeroCountsAndSevenSafeDays() throws Exception {
        mockMvc.perform(get("/api/v1/dashboard").with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.summary.singleAnalysisCount").value(0))
                .andExpect(jsonPath("$.summary.comparisonSessionCount").value(0))
                .andExpect(jsonPath("$.summary.totalInferenceCount").value(0))
                .andExpect(jsonPath("$.dailyUsage.length()").value(7))
                .andExpect(jsonPath("$.recentActivities.length()").value(0));
    }

    @Test
    void dashboardMapsDailyModelAndPredictionUsage() throws Exception {
        when(dashboardService.userDashboard("user-id", "User A"))
                .thenReturn(populatedDashboard());

        mockMvc.perform(get("/api/v1/dashboard").with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.dailyUsage[0].count").value(3))
                .andExpect(jsonPath("$.modelUsage.baseline").value(4))
                .andExpect(jsonPath("$.modelUsage.vmamba").value(2))
                .andExpect(jsonPath("$.predictionUsage.detected").value(5))
                .andExpect(jsonPath("$.predictionUsage.notDetected").value(1));
    }

    @Test
    void dashboardNormalizesConfidenceAndLimitsRecentActivities() throws Exception {
        when(dashboardService.userDashboard("user-id", "User A"))
                .thenReturn(populatedDashboard());

        mockMvc.perform(get("/api/v1/dashboard").with(user(principal)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.summary.averageDetectedConfidence").value(0.825))
                .andExpect(jsonPath("$.recentActivities.length()").value(10))
                .andExpect(jsonPath("$.recentActivities[0].confidence").value(0.8));
    }

    @Test
    void patchProfileWithoutCsrfReturns403() throws Exception {
        mockMvc.perform(patch("/api/v1/me")
                        .with(user(principal))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(profileJson("New Name", "user@example.com")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void patchProfileAsGuestReturns401() throws Exception {
        mockMvc.perform(patch("/api/v1/me")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(profileJson("New Name", "user@example.com")))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void updateFullNameReturnsNewUserAndKeepsSession() throws Exception {
        MockHttpSession session = loginSession(OLD_PASSWORD);

        mockMvc.perform(patch("/api/v1/me")
                        .session(session)
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(profileJson("  Nguyễn   Văn B  ", "user@example.com")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.fullName").value("Nguyễn Văn B"))
                .andExpect(jsonPath("$.reauthenticationRequired").value(false));

        assertFalse(session.isInvalid());
    }

    @Test
    void updateEmailNormalizesAndRequiresReauthentication() throws Exception {
        MockHttpSession session = loginSession(OLD_PASSWORD);

        mockMvc.perform(patch("/api/v1/me")
                        .session(session)
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(profileJson("User A", " NEW@Example.COM ")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.email").value("new@example.com"))
                .andExpect(jsonPath("$.reauthenticationRequired").value(true))
                .andExpect(header().string("Set-Cookie",
                        org.hamcrest.Matchers.containsString("Max-Age=0")));

        assertTrue(session.isInvalid());
    }

    @Test
    void duplicateProfileEmailReturns409() throws Exception {
        UserAccount other = account("other-id", "Other", "used@example.com", OLD_PASSWORD);
        when(userAccountRepository.findByEmailIgnoreCase("used@example.com"))
                .thenReturn(Optional.of(other));

        mockMvc.perform(patch("/api/v1/me")
                        .with(user(principal))
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(profileJson("User A", "used@example.com")))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("EMAIL_ALREADY_EXISTS"))
                .andExpect(jsonPath("$.fieldErrors.email").exists());
    }

    @Test
    void profilePayloadCannotChangeRoleOrExposePasswordHash() throws Exception {
        mockMvc.perform(patch("/api/v1/me")
                        .with(user(principal))
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "fullName": "User A",
                                  "email": "user@example.com",
                                  "role": "ADMIN",
                                  "passwordHash": "leak"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.role").value("USER"))
                .andExpect(content().string(org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("passwordHash")
                )));

        assertTrue(account.getRole() == UserRole.USER);
    }

    @Test
    void putPasswordWithoutCsrfReturns403() throws Exception {
        mockMvc.perform(put("/api/v1/me/password")
                        .with(user(principal))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(passwordJson(OLD_PASSWORD, NEW_PASSWORD, NEW_PASSWORD)))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void wrongCurrentPasswordReturnsStableCode() throws Exception {
        mockMvc.perform(put("/api/v1/me/password")
                        .with(user(principal))
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(passwordJson("WrongPass123", NEW_PASSWORD, NEW_PASSWORD)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("CURRENT_PASSWORD_INCORRECT"));
    }

    @Test
    void passwordMismatchReturnsValidationError() throws Exception {
        mockMvc.perform(put("/api/v1/me/password")
                        .with(user(principal))
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(passwordJson(OLD_PASSWORD, NEW_PASSWORD, "Different789")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.fieldErrors.confirmPassword").exists());
    }

    @Test
    void passwordReuseReturnsStableCode() throws Exception {
        mockMvc.perform(put("/api/v1/me/password")
                        .with(user(principal))
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(passwordJson(OLD_PASSWORD, OLD_PASSWORD, OLD_PASSWORD)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("PASSWORD_REUSE_NOT_ALLOWED"));
    }

    @Test
    void successfulPasswordChangeInvalidatesSession() throws Exception {
        MockHttpSession session = loginSession(OLD_PASSWORD);

        mockMvc.perform(put("/api/v1/me/password")
                        .session(session)
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(passwordJson(OLD_PASSWORD, NEW_PASSWORD, NEW_PASSWORD)))
                .andExpect(status().isNoContent())
                .andExpect(header().string("Set-Cookie",
                        org.hamcrest.Matchers.containsString("Max-Age=0")));

        assertTrue(session.isInvalid());
        assertTrue(passwordEncoder.matches(NEW_PASSWORD, account.getPasswordHash()));
    }

    @Test
    void meReturns401AfterPasswordChange() throws Exception {
        MockHttpSession session = loginSession(OLD_PASSWORD);
        mockMvc.perform(put("/api/v1/me/password")
                        .session(session)
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(passwordJson(OLD_PASSWORD, NEW_PASSWORD, NEW_PASSWORD)))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/v1/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void oldPasswordFailsAndNewPasswordAuthenticatesAfterChange() throws Exception {
        mockMvc.perform(put("/api/v1/me/password")
                        .with(user(principal))
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(passwordJson(OLD_PASSWORD, NEW_PASSWORD, NEW_PASSWORD)))
                .andExpect(status().isNoContent());

        performLogin(OLD_PASSWORD).andExpect(status().isUnauthorized());
        performLogin(NEW_PASSWORD)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.email").value("user@example.com"));
    }

    @Test
    void webProfileFlowStillInvalidatesAndRedirects() throws Exception {
        MockHttpSession session = loginSession(OLD_PASSWORD);

        mockMvc.perform(post("/profile")
                        .session(session)
                        .with(csrf())
                        .param("fullName", "Web User")
                        .param("email", "user@example.com"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login?profileUpdated"));

        assertTrue(session.isInvalid());
    }

    @Test
    void webPasswordFlowStillInvalidatesAndRedirects() throws Exception {
        MockHttpSession session = loginSession(OLD_PASSWORD);

        mockMvc.perform(post("/profile/change-password")
                        .session(session)
                        .with(csrf())
                        .param("currentPassword", OLD_PASSWORD)
                        .param("newPassword", NEW_PASSWORD)
                        .param("confirmNewPassword", NEW_PASSWORD))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login?passwordChanged"));

        assertTrue(session.isInvalid());
    }

    private org.springframework.test.web.servlet.ResultActions performLogin(
            String password) throws Exception {
        return mockMvc.perform(post("/api/v1/auth/login")
                .with(csrf())
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {
                          "email": "user@example.com",
                          "password": "%s"
                        }
                        """.formatted(password)));
    }

    private MockHttpSession loginSession(String password) throws Exception {
        MvcResult result = performLogin(password)
                .andExpect(status().isOk())
                .andReturn();
        return (MockHttpSession) result.getRequest().getSession(false);
    }

    private String profileJson(String fullName, String email) {
        return """
                {
                  "fullName": "%s",
                  "email": "%s"
                }
                """.formatted(fullName, email);
    }

    private String passwordJson(String current, String next, String confirmation) {
        return """
                {
                  "currentPassword": "%s",
                  "newPassword": "%s",
                  "confirmPassword": "%s"
                }
                """.formatted(current, next, confirmation);
    }

    private UserDashboardView emptyDashboard() {
        LocalDate start = LocalDate.now().minusDays(6);
        List<DailyUsageView> days = new ArrayList<>();
        for (int index = 0; index < 7; index++) {
            days.add(new DailyUsageView(start.plusDays(index), "", 0, 0));
        }
        return new UserDashboardView(
                "User A",
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0,
                "Chưa có dữ liệu",
                days,
                List.of()
        );
    }

    private UserDashboardView populatedDashboard() {
        List<RecentActivityView> activities = new ArrayList<>();
        for (int index = 0; index < 10; index++) {
            activities.add(new RecentActivityView(
                    "diagnosis-" + (index + 1),
                    null,
                    "sample-" + index + ".jpg",
                    "YOLO26n-seg",
                    "Baseline",
                    "Phân tích đơn",
                    true,
                    80,
                    120,
                    LocalDateTime.now(),
                    "/diagnoses/diagnosis-" + (index + 1),
                    null,
                    "User A",
                    1,
                    2
            ));
        }
        return new UserDashboardView(
                "User A",
                2, 2, 6, 5, 1, 4, 2, 12,
                145.5, 82.5, 83.333,
                "YOLO26n-seg",
                List.of(new DailyUsageView(LocalDate.now(), "Hôm nay", 3, 100)),
                activities
        );
    }

    private UserAccount account(
            String id,
            String fullName,
            String email,
            String rawPassword) {
        UserAccount user = new UserAccount();
        user.setId(id);
        user.setFullName(fullName);
        user.setEmail(email);
        user.setPasswordHash(passwordEncoder.encode(rawPassword));
        user.setRole(UserRole.USER);
        user.setEnabled(true);
        user.setCreatedAt(LocalDateTime.now().minusDays(5));
        user.setUpdatedAt(LocalDateTime.now());
        return user;
    }
}
