package com.polyp.polypweb.api;

import com.polyp.polypweb.api.dto.ApiCsrfResponse;
import com.polyp.polypweb.api.dto.ApiLoginRequest;
import com.polyp.polypweb.api.dto.ApiLoginResponse;
import com.polyp.polypweb.api.dto.ApiRegisterRequest;
import com.polyp.polypweb.api.dto.ApiRegisterResponse;
import com.polyp.polypweb.api.dto.ApiUserResponse;
import com.polyp.polypweb.api.error.ApiAuthenticationException;
import com.polyp.polypweb.api.error.ApiValidationException;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.dto.RegisterForm;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.UserAccountService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.DisabledException;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.web.authentication.logout.SecurityContextLogoutHandler;
import org.springframework.security.web.authentication.session.SessionAuthenticationStrategy;
import org.springframework.security.web.context.SecurityContextRepository;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.Map;

@RestController
@RequestMapping(value = "/api/v1", produces = MediaType.APPLICATION_JSON_VALUE)
public class ApiAuthController {

    private final UserAccountService userAccountService;
    private final AuthenticationManager authenticationManager;
    private final SessionAuthenticationStrategy sessionAuthenticationStrategy;
    private final SecurityContextRepository securityContextRepository;

    public ApiAuthController(
            UserAccountService userAccountService,
            AuthenticationManager authenticationManager,
            SessionAuthenticationStrategy sessionAuthenticationStrategy,
            SecurityContextRepository securityContextRepository) {
        this.userAccountService = userAccountService;
        this.authenticationManager = authenticationManager;
        this.sessionAuthenticationStrategy = sessionAuthenticationStrategy;
        this.securityContextRepository = securityContextRepository;
    }

    @GetMapping("/auth/csrf")
    public ResponseEntity<ApiCsrfResponse> csrf(CsrfToken csrfToken) {
        ApiCsrfResponse response = new ApiCsrfResponse(
                csrfToken.getToken(),
                csrfToken.getHeaderName(),
                csrfToken.getParameterName()
        );
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(response);
    }

    @PostMapping(
            value = "/auth/register",
            consumes = MediaType.APPLICATION_JSON_VALUE
    )
    public ResponseEntity<ApiRegisterResponse> register(
            @Valid @RequestBody ApiRegisterRequest request) {
        if (!request.password().equals(request.confirmPassword())) {
            throw new ApiValidationException(
                    Map.of("confirmPassword", "Mật khẩu xác nhận chưa khớp.")
            );
        }
        UserAccount account = userAccountService.register(toRegisterForm(request));
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(new ApiRegisterResponse("Đăng ký thành công.", account.getEmail()));
    }

    @PostMapping(
            value = "/auth/login",
            consumes = MediaType.APPLICATION_JSON_VALUE
    )
    public ApiLoginResponse login(
            @Valid @RequestBody ApiLoginRequest request,
            HttpServletRequest servletRequest,
            HttpServletResponse servletResponse) {
        Authentication authentication;
        try {
            authentication = authenticationManager.authenticate(
                    UsernamePasswordAuthenticationToken.unauthenticated(
                            UserAccountService.normalizeEmail(request.email()),
                            request.password()
                    )
            );
        } catch (DisabledException exception) {
            throw new ApiAuthenticationException(
                    HttpStatus.FORBIDDEN,
                    "ACCOUNT_DISABLED",
                    "Tài khoản đã bị khóa."
            );
        } catch (AuthenticationException exception) {
            throw new ApiAuthenticationException(
                    HttpStatus.UNAUTHORIZED,
                    "INVALID_CREDENTIALS",
                    "Email hoặc mật khẩu không đúng."
            );
        }

        sessionAuthenticationStrategy.onAuthentication(
                authentication,
                servletRequest,
                servletResponse
        );
        SecurityContext context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(authentication);
        SecurityContextHolder.setContext(context);
        securityContextRepository.saveContext(
                context,
                servletRequest,
                servletResponse
        );

        CurrentUserPrincipal principal = (CurrentUserPrincipal) authentication.getPrincipal();
        UserAccount account = userAccountService.findById(principal.getUserId());
        return new ApiLoginResponse(ApiUserResponse.from(account));
    }

    @GetMapping("/me")
    public ApiUserResponse me(@AuthenticationPrincipal CurrentUserPrincipal principal) {
        return ApiUserResponse.from(userAccountService.findById(principal.getUserId()));
    }

    @PostMapping("/auth/logout")
    public ResponseEntity<Void> logout(
            Authentication authentication,
            HttpServletRequest request,
            HttpServletResponse response) {
        new SecurityContextLogoutHandler().logout(request, response, authentication);
        String contextPath = request.getContextPath();
        ResponseCookie expiredCookie = ResponseCookie.from("JSESSIONID", "")
                .httpOnly(true)
                .secure(request.isSecure())
                .sameSite("Lax")
                .path(contextPath == null || contextPath.isBlank() ? "/" : contextPath)
                .maxAge(Duration.ZERO)
                .build();
        return ResponseEntity.noContent()
                .header(HttpHeaders.SET_COOKIE, expiredCookie.toString())
                .cacheControl(CacheControl.noStore())
                .build();
    }

    private RegisterForm toRegisterForm(ApiRegisterRequest request) {
        RegisterForm form = new RegisterForm();
        form.setFullName(request.fullName());
        form.setEmail(request.email());
        form.setPassword(request.password());
        form.setConfirmPassword(request.confirmPassword());
        form.setAcceptedTerms(request.acceptedTerms());
        return form;
    }
}
