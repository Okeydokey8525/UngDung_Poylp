package com.polyp.polypweb.api;

import com.polyp.polypweb.api.dto.ApiErrorResponse;
import com.polyp.polypweb.api.error.ApiAuthenticationException;
import com.polyp.polypweb.api.error.ApiValidationException;
import com.polyp.polypweb.exception.AccountOperationException;
import com.polyp.polypweb.exception.DuplicateEmailException;
import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.exception.UploadValidationException;
import com.polyp.polypweb.service.ModelComparisonException;
import com.polyp.polypweb.exception.PasswordOperationException;
import com.polyp.polypweb.web.RequestCorrelationFilter;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.multipart.support.MissingServletRequestPartException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@RestControllerAdvice(basePackages = "com.polyp.polypweb.api")
public class ApiExceptionHandler {

    private static final Logger LOGGER = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiErrorResponse> validation(
            MethodArgumentNotValidException exception,
            HttpServletRequest request) {
        Map<String, String> fieldErrors = new LinkedHashMap<>();
        exception.getBindingResult().getFieldErrors().forEach(error ->
                fieldErrors.putIfAbsent(error.getField(), error.getDefaultMessage())
        );
        return error(
                request,
                HttpStatus.BAD_REQUEST,
                "VALIDATION_ERROR",
                "Dữ liệu không hợp lệ.",
                fieldErrors
        );
    }

    @ExceptionHandler(ApiValidationException.class)
    public ResponseEntity<ApiErrorResponse> validation(
            ApiValidationException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.BAD_REQUEST,
                "VALIDATION_ERROR",
                "Dữ liệu không hợp lệ.",
                exception.getFieldErrors()
        );
    }

    @ExceptionHandler(DuplicateEmailException.class)
    public ResponseEntity<ApiErrorResponse> duplicateEmail(
            DuplicateEmailException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.CONFLICT,
                "EMAIL_ALREADY_EXISTS",
                "Email đã được sử dụng.",
                Map.of("email", "Email đã được sử dụng.")
        );
    }

    @ExceptionHandler(ApiAuthenticationException.class)
    public ResponseEntity<ApiErrorResponse> authentication(
            ApiAuthenticationException exception,
            HttpServletRequest request) {
        return error(
                request,
                exception.getStatus(),
                exception.getCode(),
                exception.getMessage(),
                Map.of()
        );
    }

    @ExceptionHandler(AccountOperationException.class)
    public ResponseEntity<ApiErrorResponse> accountOperation(
            AccountOperationException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.BAD_REQUEST,
                "VALIDATION_ERROR",
                exception.getMessage(),
                Map.of()
        );
    }

    @ExceptionHandler(PasswordOperationException.class)
    public ResponseEntity<ApiErrorResponse> passwordOperation(
            PasswordOperationException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.BAD_REQUEST,
                exception.getCode(),
                exception.getMessage(),
                Map.of()
        );
    }

    @ExceptionHandler(DiagnosisOperationException.class)
    public ResponseEntity<ApiErrorResponse> diagnosisOperation(
            DiagnosisOperationException exception,
            HttpServletRequest request) {
        return error(
                request,
                exception.getStatus(),
                exception.getCode(),
                exception.getMessage(),
                Map.of()
        );
    }

    @ExceptionHandler(ModelComparisonException.class)
    public ResponseEntity<ApiErrorResponse> comparisonOperation(
            ModelComparisonException exception,
            HttpServletRequest request) {
        return error(
                request,
                exception.getStatus(),
                exception.getCode(),
                exception.getMessage(),
                Map.of()
        );
    }

    @ExceptionHandler(UploadValidationException.class)
    public ResponseEntity<ApiErrorResponse> uploadValidation(
            UploadValidationException exception,
            HttpServletRequest request) {
        return error(
                request,
                exception.getStatus(),
                exception.getCode(),
                exception.getMessage(),
                Map.of()
        );
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ApiErrorResponse> accessDenied(
            AccessDeniedException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.FORBIDDEN,
                "ACCESS_DENIED",
                "Bạn không có quyền truy cập tài nguyên này.",
                Map.of()
        );
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    public ResponseEntity<ApiErrorResponse> uploadTooLarge(
            MaxUploadSizeExceededException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.PAYLOAD_TOO_LARGE,
                "FILE_TOO_LARGE",
                "Dung lượng ảnh vượt quá 10 MB.",
                Map.of()
        );
    }

    @ExceptionHandler(MissingServletRequestPartException.class)
    public ResponseEntity<ApiErrorResponse> missingPart(
            MissingServletRequestPartException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.BAD_REQUEST,
                "EMPTY_FILE",
                "Vui lòng chọn một ảnh không rỗng.",
                Map.of()
        );
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiErrorResponse> invalidJson(
            HttpMessageNotReadableException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.BAD_REQUEST,
                "INVALID_JSON",
                "Nội dung JSON không hợp lệ.",
                Map.of()
        );
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    public ResponseEntity<ApiErrorResponse> unsupportedMedia(
            HttpMediaTypeNotSupportedException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                "UNSUPPORTED_MEDIA_TYPE",
                "Content-Type không được hỗ trợ.",
                Map.of()
        );
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    public ResponseEntity<ApiErrorResponse> methodNotAllowed(
            HttpRequestMethodNotSupportedException exception,
            HttpServletRequest request) {
        return error(
                request,
                HttpStatus.METHOD_NOT_ALLOWED,
                "METHOD_NOT_ALLOWED",
                "Phương thức HTTP không được hỗ trợ.",
                Map.of()
        );
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiErrorResponse> internalError(
            Exception exception,
            HttpServletRequest request) {
        LOGGER.error(
                "Unhandled API error requestId={} method={} path={} type={}",
                requestId(request),
                request.getMethod(),
                request.getRequestURI(),
                exception.getClass().getSimpleName()
        );
        return error(
                request,
                HttpStatus.INTERNAL_SERVER_ERROR,
                "INTERNAL_ERROR",
                "Đã xảy ra lỗi, vui lòng thử lại.",
                Map.of()
        );
    }

    private ResponseEntity<ApiErrorResponse> error(
            HttpServletRequest request,
            HttpStatus status,
            String code,
            String message,
            Map<String, String> fieldErrors) {
        return ResponseEntity.status(status)
                .contentType(MediaType.APPLICATION_JSON)
                .header("Cache-Control", "no-store")
                .body(new ApiErrorResponse(
                        Instant.now(),
                        status.value(),
                        code,
                        message,
                        fieldErrors,
                        requestId(request)
                ));
    }

    private String requestId(HttpServletRequest request) {
        Object value = request.getAttribute(RequestCorrelationFilter.REQUEST_ID_ATTRIBUTE);
        return value == null ? "" : value.toString();
    }
}
