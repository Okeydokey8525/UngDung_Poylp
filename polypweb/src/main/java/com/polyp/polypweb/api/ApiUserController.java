package com.polyp.polypweb.api;

import com.polyp.polypweb.api.dto.ApiPasswordChangeRequest;
import com.polyp.polypweb.api.dto.ApiProfileUpdateRequest;
import com.polyp.polypweb.api.dto.ApiProfileUpdateResponse;
import com.polyp.polypweb.api.dto.ApiUserResponse;
import com.polyp.polypweb.api.error.ApiValidationException;
import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.dto.ChangePasswordForm;
import com.polyp.polypweb.dto.ProfileUpdateForm;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.UserAccountService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.web.authentication.logout.SecurityContextLogoutHandler;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.Map;

@RestController
@RequestMapping(value = "/api/v1", produces = MediaType.APPLICATION_JSON_VALUE)
public class ApiUserController {

    private final UserAccountService userAccountService;

    public ApiUserController(UserAccountService userAccountService) {
        this.userAccountService = userAccountService;
    }

    @PatchMapping(value = "/me", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<ApiProfileUpdateResponse> updateProfile(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            Authentication authentication,
            @Valid @RequestBody ApiProfileUpdateRequest request,
            HttpServletRequest servletRequest,
            HttpServletResponse servletResponse) {
        boolean emailChanged = !UserAccountService.normalizeEmail(principal.getEmail())
                .equals(request.email());
        UserAccount account = userAccountService.updateProfile(
                principal.getUserId(),
                toProfileForm(request)
        );
        ApiProfileUpdateResponse body = new ApiProfileUpdateResponse(
                ApiUserResponse.from(account),
                emailChanged
        );
        if (emailChanged) {
            endSession(authentication, servletRequest, servletResponse);
            return ResponseEntity.ok()
                    .header(HttpHeaders.SET_COOKIE, expiredSessionCookie(servletRequest))
                    .cacheControl(CacheControl.noStore())
                    .body(body);
        }
        return ResponseEntity.ok()
                .cacheControl(CacheControl.noStore())
                .body(body);
    }

    @PutMapping(value = "/me/password", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<Void> changePassword(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            Authentication authentication,
            @Valid @RequestBody ApiPasswordChangeRequest request,
            HttpServletRequest servletRequest,
            HttpServletResponse servletResponse) {
        if (!request.newPassword().equals(request.confirmPassword())) {
            throw new ApiValidationException(
                    Map.of("confirmPassword", "Mật khẩu mới xác nhận chưa khớp.")
            );
        }
        userAccountService.changePassword(principal.getUserId(), toPasswordForm(request));
        endSession(authentication, servletRequest, servletResponse);
        return ResponseEntity.noContent()
                .header(HttpHeaders.SET_COOKIE, expiredSessionCookie(servletRequest))
                .cacheControl(CacheControl.noStore())
                .build();
    }

    private ProfileUpdateForm toProfileForm(ApiProfileUpdateRequest request) {
        ProfileUpdateForm form = new ProfileUpdateForm();
        form.setFullName(request.fullName());
        form.setEmail(request.email());
        return form;
    }

    private ChangePasswordForm toPasswordForm(ApiPasswordChangeRequest request) {
        ChangePasswordForm form = new ChangePasswordForm();
        form.setCurrentPassword(request.currentPassword());
        form.setNewPassword(request.newPassword());
        form.setConfirmNewPassword(request.confirmPassword());
        return form;
    }

    private void endSession(
            Authentication authentication,
            HttpServletRequest request,
            HttpServletResponse response) {
        new SecurityContextLogoutHandler().logout(request, response, authentication);
    }

    private String expiredSessionCookie(HttpServletRequest request) {
        String contextPath = request.getContextPath();
        return ResponseCookie.from("JSESSIONID", "")
                .httpOnly(true)
                .secure(request.isSecure())
                .sameSite("Lax")
                .path(contextPath == null || contextPath.isBlank() ? "/" : contextPath)
                .maxAge(Duration.ZERO)
                .build()
                .toString();
    }
}
