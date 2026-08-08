package com.polyp.polypweb;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.config.AdminSeedRunner;
import com.polyp.polypweb.config.DiagnosisHistoryIndexInitializer;
import com.polyp.polypweb.config.UserAccountIndexInitializer;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.UserAccountRepository;
import com.polyp.polypweb.service.DashboardService;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.FileStorageService;
import com.polyp.polypweb.service.ModelComparisonService;
import jakarta.servlet.http.HttpSession;
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
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.redirectedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class ApiAuthenticationIntegrationTests {

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
    private UserAccount disabledUser;

    @BeforeEach
    void setUp() {
        enabledUser = account("user-id", "user@example.com", true);
        disabledUser = account("disabled-id", "disabled@example.com", false);
        when(userAccountRepository.findByEmailIgnoreCase("user@example.com"))
                .thenReturn(Optional.of(enabledUser));
        when(userAccountRepository.findByEmailIgnoreCase("disabled@example.com"))
                .thenReturn(Optional.of(disabledUser));
        when(userAccountRepository.findById("user-id")).thenReturn(Optional.of(enabledUser));
        when(userAccountRepository.findById("disabled-id")).thenReturn(Optional.of(disabledUser));
        when(userAccountRepository.save(any(UserAccount.class))).thenAnswer(invocation -> {
            UserAccount account = invocation.getArgument(0);
            if (account.getId() == null) {
                account.setId("registered-id");
            }
            return account;
        });
        when(mongoHealthIndicator.health()).thenReturn(Health.up().build());
    }

    @Test
    void csrfReturnsRealTokenAndNames() throws Exception {
        mockMvc.perform(get("/api/v1/auth/csrf"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.token").isNotEmpty())
                .andExpect(jsonPath("$.headerName").value("X-CSRF-TOKEN"))
                .andExpect(jsonPath("$.parameterName").value("_csrf"));
    }

    @Test
    void csrfResponseIsNotCacheable() throws Exception {
        mockMvc.perform(get("/api/v1/auth/csrf"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", containsString("no-store")));
    }

    @Test
    void registerWithoutCsrfReturnsJson403() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validRegisterJson()))
                .andExpect(status().isForbidden())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void validRegisterReturns201() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validRegisterJson()))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.message").value("Đăng ký thành công."))
                .andExpect(jsonPath("$.email").value("new@example.com"));
    }

    @Test
    void registerAlwaysCreatesEnabledUserWithBcryptPassword() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validRegisterJson()))
                .andExpect(status().isCreated());

        org.mockito.ArgumentCaptor<UserAccount> captor =
                org.mockito.ArgumentCaptor.forClass(UserAccount.class);
        org.mockito.Mockito.verify(userAccountRepository).save(captor.capture());
        assertEquals(UserRole.USER, captor.getValue().getRole());
        assertTrue(captor.getValue().isEnabled());
        assertTrue(passwordEncoder.matches("Password123", captor.getValue().getPasswordHash()));
    }

    @Test
    void registerCannotCreateAdminFromUnknownJsonFields() throws Exception {
        String body = validRegisterJson().replace(
                "\"acceptedTerms\":true",
                "\"acceptedTerms\":true,\"role\":\"ADMIN\",\"enabled\":false"
        );
        mockMvc.perform(post("/api/v1/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isCreated());

        org.mockito.ArgumentCaptor<UserAccount> captor =
                org.mockito.ArgumentCaptor.forClass(UserAccount.class);
        org.mockito.Mockito.verify(userAccountRepository).save(captor.capture());
        assertEquals(UserRole.USER, captor.getValue().getRole());
        assertTrue(captor.getValue().isEnabled());
    }

    @Test
    void registerNormalizesEmailToLowercase() throws Exception {
        String body = validRegisterJson().replace(
                "new@example.com",
                "  New@Example.COM  "
        );
        mockMvc.perform(post("/api/v1/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.email").value("new@example.com"));
    }

    @Test
    void duplicateRegisterReturns409() throws Exception {
        when(userAccountRepository.existsByEmailIgnoreCase("new@example.com")).thenReturn(true);
        mockMvc.perform(post("/api/v1/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validRegisterJson()))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("EMAIL_ALREADY_EXISTS"))
                .andExpect(jsonPath("$.fieldErrors.email").exists());
    }

    @Test
    void registerPasswordMismatchReturns400() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validRegisterJson().replace(
                                "\"confirmPassword\":\"Password123\"",
                                "\"confirmPassword\":\"Different123\""
                        )))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.fieldErrors.confirmPassword").exists());
    }

    @Test
    void registerWithoutAcceptedTermsReturns400() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validRegisterJson().replace(
                                "\"acceptedTerms\":true",
                                "\"acceptedTerms\":false"
                        )))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.fieldErrors.acceptedTerms").exists());
    }

    @Test
    void loginWithoutCsrfReturnsJson403() throws Exception {
        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validLoginJson()))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void validLoginReturnsCurrentUser() throws Exception {
        mockMvc.perform(post("/api/v1/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validLoginJson()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.id").value("user-id"))
                .andExpect(jsonPath("$.user.email").value("user@example.com"))
                .andExpect(jsonPath("$.user.role").value("USER"));
    }

    @Test
    void validLoginCreatesAuthenticatedSessionContext() throws Exception {
        MvcResult result = performLogin();
        HttpSession session = result.getRequest().getSession(false);
        assertNotNull(session);
        assertNotNull(session.getAttribute(
                HttpSessionSecurityContextRepository.SPRING_SECURITY_CONTEXT_KEY
        ));
    }

    @Test
    void loginRotatesExistingSessionId() throws Exception {
        MvcResult csrfResult = mockMvc.perform(get("/api/v1/auth/csrf"))
                .andExpect(status().isOk())
                .andReturn();
        MockHttpSession session = (MockHttpSession) csrfResult.getRequest().getSession(false);
        assertNotNull(session);
        String originalId = session.getId();

        mockMvc.perform(post("/api/v1/auth/login")
                        .session(session)
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validLoginJson()))
                .andExpect(status().isOk());

        assertNotEquals(originalId, session.getId());
    }

    @Test
    void invalidCredentialsReturnGeneric401() throws Exception {
        mockMvc.perform(post("/api/v1/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"missing@example.com","password":"Wrong123"}
                                """))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("INVALID_CREDENTIALS"))
                .andExpect(jsonPath("$.message").value("Email hoặc mật khẩu không đúng."));
    }

    @Test
    void disabledAccountReturns403() throws Exception {
        mockMvc.perform(post("/api/v1/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"email":"disabled@example.com","password":"Password123"}
                                """))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("ACCOUNT_DISABLED"));
    }

    @Test
    void loginResponseDoesNotExposePasswordOrSessionId() throws Exception {
        mockMvc.perform(post("/api/v1/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validLoginJson()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.user.passwordHash").doesNotExist())
                .andExpect(jsonPath("$.sessionId").doesNotExist())
                .andExpect(content().string(not(containsString(enabledUser.getPasswordHash()))));
    }

    @Test
    void meWithAuthenticatedSessionReturnsUser() throws Exception {
        MockHttpSession session = loginSession();
        mockMvc.perform(get("/api/v1/me").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value("user-id"))
                .andExpect(jsonPath("$.fullName").value("Regular User"))
                .andExpect(jsonPath("$.createdAt").exists())
                .andExpect(jsonPath("$.updatedAt").exists());
    }

    @Test
    void guestMeReturnsJson401() throws Exception {
        mockMvc.perform(get("/api/v1/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void logoutWithoutCsrfReturns403() throws Exception {
        mockMvc.perform(post("/api/v1/auth/logout")
                        .with(user(new com.polyp.polypweb.security.CurrentUserPrincipal(enabledUser))))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CSRF_INVALID"));
    }

    @Test
    void validLogoutReturns204AndExpiresCookie() throws Exception {
        MockHttpSession session = loginSession();
        mockMvc.perform(post("/api/v1/auth/logout")
                        .session(session)
                        .with(csrf()))
                .andExpect(status().isNoContent())
                .andExpect(header().string("Set-Cookie", containsString("JSESSIONID=")))
                .andExpect(header().string("Set-Cookie", containsString("Max-Age=0")));
        assertTrue(session.isInvalid());
    }

    @Test
    void meAfterLogoutReturns401() throws Exception {
        MockHttpSession session = loginSession();
        mockMvc.perform(post("/api/v1/auth/logout")
                        .session(session)
                        .with(csrf()))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"));
    }

    @Test
    void apiGuestNeverRedirectsToHtmlLogin() throws Exception {
        mockMvc.perform(get("/api/v1/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(header().doesNotExist("Location"))
                .andExpect(content().string(not(containsString("<html"))));
    }

    @Test
    void legacyWebLoginStillRedirects() throws Exception {
        mockMvc.perform(post("/login")
                        .with(csrf())
                        .param("email", "user@example.com")
                        .param("password", "Password123"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/"));
    }

    @Test
    void legacyWebRegisterStillRedirects() throws Exception {
        mockMvc.perform(post("/register")
                        .with(csrf())
                        .param("fullName", "New User")
                        .param("email", "new@example.com")
                        .param("password", "Password123")
                        .param("confirmPassword", "Password123")
                        .param("acceptedTerms", "true"))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login?registered"));
    }

    @Test
    void legacyWebLogoutStillRedirects() throws Exception {
        MockHttpSession session = loginSession();
        mockMvc.perform(post("/logout")
                        .session(session)
                        .with(csrf()))
                .andExpect(status().is3xxRedirection())
                .andExpect(redirectedUrl("/login?logout"));
    }

    @Test
    void legacyWebFormsStillContainCsrf() throws Exception {
        mockMvc.perform(get("/login"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("name=\"_csrf\"")));
        mockMvc.perform(get("/register"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("name=\"_csrf\"")));
    }

    @Test
    void apiErrorContainsCorrelationRequestId() throws Exception {
        mockMvc.perform(get("/api/v1/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(header().exists("X-Request-ID"))
                .andExpect(jsonPath("$.requestId").isNotEmpty());
    }

    @Test
    void apiErrorDoesNotExposeStackTraceOrExceptionClass() throws Exception {
        mockMvc.perform(post("/api/v1/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{invalid-json"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(not(containsString("Exception"))))
                .andExpect(content().string(not(containsString("stackTrace"))))
                .andExpect(content().string(not(containsString("java."))));
    }

    @Test
    void currentUserApiNeverExposesPasswordHash() throws Exception {
        MockHttpSession session = loginSession();
        mockMvc.perform(get("/api/v1/me").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.passwordHash").doesNotExist())
                .andExpect(content().string(not(containsString(enabledUser.getPasswordHash()))));
    }

    private MvcResult performLogin() throws Exception {
        return mockMvc.perform(post("/api/v1/auth/login")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validLoginJson()))
                .andExpect(status().isOk())
                .andReturn();
    }

    private MockHttpSession loginSession() throws Exception {
        return (MockHttpSession) performLogin().getRequest().getSession(false);
    }

    private String validRegisterJson() {
        return """
                {
                  "fullName":"New User",
                  "email":"new@example.com",
                  "password":"Password123",
                  "confirmPassword":"Password123",
                  "acceptedTerms":true
                }
                """;
    }

    private String validLoginJson() {
        return """
                {"email":"user@example.com","password":"Password123"}
                """;
    }

    private UserAccount account(String id, String email, boolean enabled) {
        UserAccount account = new UserAccount();
        account.setId(id);
        account.setFullName("Regular User");
        account.setEmail(email);
        account.setPasswordHash(passwordEncoder.encode("Password123"));
        account.setRole(UserRole.USER);
        account.setEnabled(enabled);
        account.setCreatedAt(LocalDateTime.now());
        account.setUpdatedAt(LocalDateTime.now());
        return account;
    }
}
