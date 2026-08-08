package com.polyp.polypweb.service;

import com.polyp.polypweb.exception.UploadValidationException;
import org.springframework.http.HttpStatus;
import org.springframework.web.multipart.MultipartFile;

import java.util.Locale;
import java.util.Set;

public final class ImageUploadValidator {

    private static final long MAX_UPLOAD_BYTES = 10L * 1024 * 1024;
    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of("image/jpeg", "image/png");
    private static final Set<String> ALLOWED_EXTENSIONS = Set.of("jpg", "jpeg", "png");

    private ImageUploadValidator() {
    }

    public static String validate(MultipartFile image, FileStorageService storageService) {
        if (image == null || image.isEmpty()) {
            throw new UploadValidationException(
                    HttpStatus.BAD_REQUEST,
                    "EMPTY_FILE",
                    "Vui lòng chọn một ảnh không rỗng."
            );
        }
        if (image.getSize() > MAX_UPLOAD_BYTES) {
            throw new UploadValidationException(
                    HttpStatus.PAYLOAD_TOO_LARGE,
                    "FILE_TOO_LARGE",
                    "Dung lượng ảnh vượt quá 10 MB."
            );
        }
        if (!ALLOWED_CONTENT_TYPES.contains(image.getContentType())) {
            throw new UploadValidationException(
                    HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                    "UNSUPPORTED_MEDIA_TYPE",
                    "Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG."
            );
        }

        String fileName = safeFileName(image.getOriginalFilename());
        int dot = fileName.lastIndexOf('.');
        String extension = dot < 0 ? "" : fileName.substring(dot + 1).toLowerCase(Locale.ROOT);
        if (!ALLOWED_EXTENSIONS.contains(extension)) {
            throw new UploadValidationException(
                    HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                    "UNSUPPORTED_MEDIA_TYPE",
                    "Phần mở rộng ảnh phải là JPG, JPEG hoặc PNG."
            );
        }
        if (("image/png".equals(image.getContentType()) && !"png".equals(extension))
                || ("image/jpeg".equals(image.getContentType())
                && !("jpg".equals(extension) || "jpeg".equals(extension)))) {
            throw new UploadValidationException(
                    HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                    "UNSUPPORTED_MEDIA_TYPE",
                    "MIME và phần mở rộng ảnh không khớp."
            );
        }

        try {
            storageService.validateOriginal(image);
        } catch (StorageException exception) {
            throw new UploadValidationException(
                    HttpStatus.UNPROCESSABLE_ENTITY,
                    "INVALID_IMAGE",
                    "Nội dung tệp không phải ảnh JPG, JPEG hoặc PNG hợp lệ.",
                    exception
            );
        }
        return fileName;
    }

    private static String safeFileName(String originalFileName) {
        if (originalFileName == null || originalFileName.isBlank()
                || originalFileName.contains("\r") || originalFileName.contains("\n")) {
            throw invalidName();
        }
        String normalized = originalFileName.replace('\\', '/');
        String baseName = normalized.substring(normalized.lastIndexOf('/') + 1).trim();
        if (baseName.isBlank() || baseName.length() > 255
                || ".".equals(baseName) || "..".equals(baseName)) {
            throw invalidName();
        }
        return baseName;
    }

    private static UploadValidationException invalidName() {
        return new UploadValidationException(
                HttpStatus.UNPROCESSABLE_ENTITY,
                "INVALID_IMAGE",
                "Tên tệp ảnh không hợp lệ."
        );
    }
}
