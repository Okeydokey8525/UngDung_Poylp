package com.polyp.polypweb.controller;

import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.service.ModelComparisonException;
import com.polyp.polypweb.service.StorageException;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.ui.Model;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@ControllerAdvice
public class GlobalErrorHandler {

    private static final Logger LOGGER = LoggerFactory.getLogger(GlobalErrorHandler.class);

    @ExceptionHandler({
            MissingServletRequestParameterException.class,
            MethodArgumentNotValidException.class,
            MethodArgumentTypeMismatchException.class
    })
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public String badRequest(Exception exception, HttpServletRequest request, Model model) {
        logClientError(HttpStatus.BAD_REQUEST, exception, request);
        prepare(model, HttpStatus.BAD_REQUEST);
        return "error/400";
    }

    @ExceptionHandler(AccessDeniedException.class)
    @ResponseStatus(HttpStatus.FORBIDDEN)
    public String forbidden(AccessDeniedException exception, HttpServletRequest request, Model model) {
        logClientError(HttpStatus.FORBIDDEN, exception, request);
        prepare(model, HttpStatus.FORBIDDEN);
        return "error/403";
    }

    @ExceptionHandler(NoResourceFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public String notFound(NoResourceFoundException exception, HttpServletRequest request, Model model) {
        logClientError(HttpStatus.NOT_FOUND, exception, request);
        prepare(model, HttpStatus.NOT_FOUND);
        return "error/404";
    }

    @ExceptionHandler(MaxUploadSizeExceededException.class)
    @ResponseStatus(HttpStatus.CONTENT_TOO_LARGE)
    public String payloadTooLarge(
            MaxUploadSizeExceededException exception,
            HttpServletRequest request,
            Model model) {
        logClientError(HttpStatus.CONTENT_TOO_LARGE, exception, request);
        prepare(model, HttpStatus.CONTENT_TOO_LARGE);
        return "error/413";
    }

    @ExceptionHandler(HttpMediaTypeNotSupportedException.class)
    @ResponseStatus(HttpStatus.UNSUPPORTED_MEDIA_TYPE)
    public String unsupportedMedia(
            HttpMediaTypeNotSupportedException exception,
            HttpServletRequest request,
            Model model) {
        logClientError(HttpStatus.UNSUPPORTED_MEDIA_TYPE, exception, request);
        prepare(model, HttpStatus.UNSUPPORTED_MEDIA_TYPE);
        return "error/415";
    }

    @ExceptionHandler(StorageException.class)
    @ResponseStatus(HttpStatus.UNPROCESSABLE_CONTENT)
    public String invalidImage(StorageException exception, HttpServletRequest request, Model model) {
        logClientError(HttpStatus.UNPROCESSABLE_CONTENT, exception, request);
        prepare(model, HttpStatus.UNPROCESSABLE_CONTENT);
        return "error/422";
    }

    @ExceptionHandler({
            AiServiceException.class,
            ModelComparisonException.class,
            DataAccessException.class
    })
    @ResponseStatus(HttpStatus.SERVICE_UNAVAILABLE)
    public String dependencyUnavailable(
            RuntimeException exception,
            HttpServletRequest request,
            Model model) {
        LOGGER.warn(
                "Dependency unavailable method={} path={} type={}",
                request.getMethod(),
                request.getRequestURI(),
                exception.getClass().getSimpleName()
        );
        prepare(model, HttpStatus.SERVICE_UNAVAILABLE);
        return "error/503";
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public String internalError(Exception exception, HttpServletRequest request, Model model) {
        LOGGER.error(
                "Unhandled request error method={} path={} type={}",
                request.getMethod(),
                request.getRequestURI(),
                exception.getClass().getSimpleName(),
                exception
        );
        prepare(model, HttpStatus.INTERNAL_SERVER_ERROR);
        return "error/500";
    }

    private void logClientError(HttpStatus status, Exception exception, HttpServletRequest request) {
        LOGGER.info(
                "Request rejected status={} method={} path={} type={}",
                status.value(),
                request.getMethod(),
                request.getRequestURI(),
                exception.getClass().getSimpleName()
        );
    }

    private void prepare(Model model, HttpStatus status) {
        model.addAttribute("pageTitle", status.getReasonPhrase());
        model.addAttribute("statusCode", status.value());
    }
}
