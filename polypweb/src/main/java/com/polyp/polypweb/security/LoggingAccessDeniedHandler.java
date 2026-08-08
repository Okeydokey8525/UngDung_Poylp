package com.polyp.polypweb.security;

import com.polyp.polypweb.api.security.ApiAccessDeniedHandler;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.access.AccessDeniedHandler;
import org.springframework.stereotype.Component;

import java.io.IOException;

@Component
public class LoggingAccessDeniedHandler implements AccessDeniedHandler {

    private static final Logger LOGGER = LoggerFactory.getLogger(LoggingAccessDeniedHandler.class);
    private final ApiAccessDeniedHandler apiAccessDeniedHandler;

    public LoggingAccessDeniedHandler(ApiAccessDeniedHandler apiAccessDeniedHandler) {
        this.apiAccessDeniedHandler = apiAccessDeniedHandler;
    }

    @Override
    public void handle(
            HttpServletRequest request,
            HttpServletResponse response,
            AccessDeniedException exception) throws IOException, ServletException {
        LOGGER.warn(
                "Từ chối truy cập userId={} method={} path={}",
                currentUserId(),
                request.getMethod(),
                request.getRequestURI()
        );
        if (isApiRequest(request)) {
            apiAccessDeniedHandler.handle(request, response, exception);
            return;
        }
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        request.getRequestDispatcher("/error/403").forward(request, response);
    }

    private boolean isApiRequest(HttpServletRequest request) {
        String contextPath = request.getContextPath();
        String prefix = (contextPath == null ? "" : contextPath) + "/api/v1/";
        return request.getRequestURI().startsWith(prefix);
    }

    private String currentUserId() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null
                && authentication.getPrincipal() instanceof CurrentUserPrincipal principal) {
            String userId = principal.getUserId();
            return userId.length() <= 8 ? userId : userId.substring(0, 8);
        }
        return "anonymous";
    }
}
