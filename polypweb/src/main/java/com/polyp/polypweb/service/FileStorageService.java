package com.polyp.polypweb.service;

import com.polyp.polypweb.config.StorageProperties;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import javax.imageio.ImageIO;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Base64;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

@Service
public class FileStorageService {

    private static final Logger LOGGER = LoggerFactory.getLogger(FileStorageService.class);
    private static final long DEFAULT_MAX_FILE_SIZE = 10L * 1024 * 1024;
    private static final long DEFAULT_MAX_RESULT_SIZE = 15L * 1024 * 1024;
    private static final String ORIGINAL_CATEGORY = "original";
    private static final String RESULTS_CATEGORY = "results";
    private static final Set<String> COMPARISON_RESULT_VARIANTS = Set.of("baseline", "vmamba");

    private final Path storageRoot;
    private final Path originalDirectory;
    private final Path resultsDirectory;
    private final long maxFileSize;
    private final long maxResultSize;

    @Autowired
    public FileStorageService(StorageProperties properties) {
        this(
                properties.getRoot(),
                properties.getMaxFileSize().toBytes(),
                properties.getMaxResultSize().toBytes()
        );
    }

    public FileStorageService(String configuredRoot) {
        this(
                Path.of(configuredRoot),
                DEFAULT_MAX_FILE_SIZE,
                DEFAULT_MAX_RESULT_SIZE
        );
    }

    private FileStorageService(Path configuredRoot, long maxFileSize, long maxResultSize) {
        Path root = configuredRoot;
        if (!root.isAbsolute()) {
            root = Path.of(System.getProperty("user.dir")).resolve(root);
        }

        this.storageRoot = root.toAbsolutePath().normalize();
        this.originalDirectory = storageRoot.resolve(ORIGINAL_CATEGORY).normalize();
        this.resultsDirectory = storageRoot.resolve(RESULTS_CATEGORY).normalize();
        this.maxFileSize = maxFileSize;
        this.maxResultSize = maxResultSize;

        ensureInsideRoot(originalDirectory);
        ensureInsideRoot(resultsDirectory);
        initializeDirectories();
    }

    private void initializeDirectories() {
        try {
            Files.createDirectories(originalDirectory);
            Files.createDirectories(resultsDirectory);
        } catch (IOException exception) {
            LOGGER.warn(
                    "Storage chưa thể khởi tạo; health sẽ báo DOWN cho đến khi quyền truy cập được khôi phục: {}",
                    exception.getClass().getSimpleName()
            );
        }
    }

    public void verifyWritable() {
        verifyDirectoryWritable(originalDirectory);
        verifyDirectoryWritable(resultsDirectory);
    }

    public String storeOriginal(MultipartFile image, UUID storageId) {
        byte[] content = readAndValidateOriginal(image);
        String extension = "image/png".equals(image.getContentType()) ? ".png" : ".jpg";
        String fileName = storageId + extension;
        writeAtomically(originalDirectory, fileName, content);
        return mediaUrl(ORIGINAL_CATEGORY, fileName);
    }

    public void validateOriginal(MultipartFile image) {
        readAndValidateOriginal(image);
    }

    public String storeResult(String resultImageBase64, UUID storageId) {
        return storeResultFile(resultImageBase64, storageId + "_result.jpg");
    }

    public String storeComparisonResult(
            String resultImageBase64,
            UUID storageId,
            String variant) {
        if (!COMPARISON_RESULT_VARIANTS.contains(variant)) {
            throw new StorageException("Loại ảnh kết quả so sánh không hợp lệ.");
        }
        return storeResultFile(
                resultImageBase64,
                storageId + "_" + variant + "_result.jpg"
        );
    }

    private String storeResultFile(String resultImageBase64, String fileName) {
        if (resultImageBase64 == null || resultImageBase64.isBlank()) {
            throw new StorageException("FastAPI không trả về ảnh overlay để lưu.");
        }

        byte[] content;
        try {
            content = Base64.getDecoder().decode(resultImageBase64);
        } catch (IllegalArgumentException exception) {
            throw new StorageException("Ảnh overlay Base64 không hợp lệ.", exception);
        }

        if (content.length == 0 || content.length > maxResultSize || !isJpeg(content) || !canDecode(content)) {
            throw new StorageException("Ảnh overlay trả về không phải JPEG hợp lệ.");
        }

        writeAtomically(resultsDirectory, fileName, content);
        return mediaUrl(RESULTS_CATEGORY, fileName);
    }

    public Optional<Resource> loadMedia(String category, String fileName) {
        Path categoryDirectory = categoryDirectory(category);
        if (categoryDirectory == null || !isValidStoredFileName(category, fileName)) {
            return Optional.empty();
        }

        Path file = categoryDirectory.resolve(fileName).normalize();
        if (!file.startsWith(categoryDirectory) || !Files.isRegularFile(file) || !Files.isReadable(file)) {
            return Optional.empty();
        }

        try {
            return Optional.of(new UrlResource(file.toUri()));
        } catch (IOException exception) {
            return Optional.empty();
        }
    }

    public Optional<Resource> loadMediaUrl(String mediaUrl) {
        Optional<Path> path = resolveMediaUrl(mediaUrl);
        if (path.isEmpty()
                || !Files.isRegularFile(path.get())
                || !Files.isReadable(path.get())) {
            return Optional.empty();
        }
        try {
            return Optional.of(new UrlResource(path.get().toUri()));
        } catch (IOException exception) {
            return Optional.empty();
        }
    }

    public void deleteQuietly(String mediaUrl) {
        try {
            deleteIfExists(mediaUrl);
        } catch (StorageException exception) {
            LOGGER.warn("Không thể xóa file storage cho URL {}", mediaUrl, exception);
        }
    }

    public boolean deleteIfExists(String mediaUrl) {
        Optional<Path> resolvedPath = resolveMediaUrl(mediaUrl);
        if (resolvedPath.isEmpty()) {
            return false;
        }
        try {
            return Files.deleteIfExists(resolvedPath.get());
        } catch (IOException exception) {
            throw new StorageException("Không thể xóa file storage.", exception);
        }
    }

    private byte[] readAndValidateOriginal(MultipartFile image) {
        if (image == null || image.isEmpty()) {
            throw new StorageException("Tệp ảnh tải lên đang rỗng.");
        }
        if (image.getSize() > maxFileSize) {
            throw new StorageException("Dung lượng ảnh vượt quá 10 MB.");
        }

        String contentType = image.getContentType();
        if (!"image/jpeg".equals(contentType) && !"image/png".equals(contentType)) {
            throw new StorageException("Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG.");
        }

        try {
            byte[] content = image.getBytes();
            boolean signatureMatches = "image/jpeg".equals(contentType) ? isJpeg(content) : isPng(content);
            if (!signatureMatches || !canDecode(content)) {
                throw new StorageException("Nội dung tệp không phải ảnh JPG, JPEG hoặc PNG hợp lệ.");
            }
            return content;
        } catch (IOException exception) {
            throw new StorageException("Không thể đọc tệp ảnh tải lên.", exception);
        }
    }

    private boolean canDecode(byte[] content) {
        try (ByteArrayInputStream input = new ByteArrayInputStream(content)) {
            return ImageIO.read(input) != null;
        } catch (IOException exception) {
            return false;
        }
    }

    private boolean isJpeg(byte[] content) {
        return content.length >= 3
                && (content[0] & 0xff) == 0xff
                && (content[1] & 0xff) == 0xd8
                && (content[2] & 0xff) == 0xff;
    }

    private boolean isPng(byte[] content) {
        int[] signature = {0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a};
        if (content.length < signature.length) {
            return false;
        }
        for (int index = 0; index < signature.length; index++) {
            if ((content[index] & 0xff) != signature[index]) {
                return false;
            }
        }
        return true;
    }

    private void writeAtomically(Path directory, String fileName, byte[] content) {
        Path target = directory.resolve(fileName).normalize();
        if (!target.startsWith(directory)) {
            throw new StorageException("Đường dẫn lưu ảnh không hợp lệ.");
        }

        Path temporary = null;
        try {
            temporary = Files.createTempFile(directory, fileName, ".tmp");
            Files.write(temporary, content);
            try {
                Files.move(
                        temporary,
                        target,
                        StandardCopyOption.ATOMIC_MOVE
                );
            } catch (AtomicMoveNotSupportedException exception) {
                Files.move(temporary, target);
            }
        } catch (IOException exception) {
            if (temporary != null) {
                try {
                    Files.deleteIfExists(temporary);
                } catch (IOException cleanupException) {
                    exception.addSuppressed(cleanupException);
                }
            }
            throw new StorageException("Không thể lưu ảnh vào storage.", exception);
        }
    }

    private void verifyDirectoryWritable(Path directory) {
        Path probe = null;
        try {
            Files.createDirectories(directory);
            if (!Files.isDirectory(directory) || !Files.isWritable(directory)) {
                throw new StorageException("Thư mục storage không thể ghi.");
            }
            probe = Files.createTempFile(directory, ".health-", ".tmp");
        } catch (IOException | SecurityException exception) {
            throw new StorageException("Không thể xác minh quyền ghi storage.", exception);
        } finally {
            if (probe != null) {
                try {
                    Files.deleteIfExists(probe);
                } catch (IOException exception) {
                    LOGGER.warn(
                            "Không thể xóa file health probe của storage: {}",
                            exception.getClass().getSimpleName()
                    );
                }
            }
        }
    }

    private Optional<Path> resolveMediaUrl(String mediaUrl) {
        if (mediaUrl == null || mediaUrl.isBlank() || !mediaUrl.startsWith("/media/")) {
            return Optional.empty();
        }

        String[] parts = mediaUrl.substring("/media/".length()).split("/", -1);
        if (parts.length != 2 || !isValidStoredFileName(parts[0], parts[1])) {
            return Optional.empty();
        }

        Path directory = categoryDirectory(parts[0]);
        if (directory == null) {
            return Optional.empty();
        }

        Path path = directory.resolve(parts[1]).normalize();
        return path.startsWith(directory) ? Optional.of(path) : Optional.empty();
    }

    private boolean isValidStoredFileName(String category, String fileName) {
        if (fileName == null || fileName.contains("/") || fileName.contains("\\")) {
            return false;
        }

        String uuidPart;
        if (ORIGINAL_CATEGORY.equals(category)) {
            if (!(fileName.endsWith(".jpg") || fileName.endsWith(".png"))) {
                return false;
            }
            uuidPart = fileName.substring(0, fileName.length() - 4);
        } else if (RESULTS_CATEGORY.equals(category)) {
            String suffix = null;
            for (String candidate : new String[]{
                    "_baseline_result.jpg",
                    "_vmamba_result.jpg",
                    "_result.jpg"
            }) {
                if (fileName.endsWith(candidate)) {
                    suffix = candidate;
                    break;
                }
            }
            if (suffix == null) {
                return false;
            }
            uuidPart = fileName.substring(0, fileName.length() - suffix.length());
        } else {
            return false;
        }

        try {
            UUID.fromString(uuidPart);
            return true;
        } catch (IllegalArgumentException exception) {
            return false;
        }
    }

    private Path categoryDirectory(String category) {
        return switch (category) {
            case ORIGINAL_CATEGORY -> originalDirectory;
            case RESULTS_CATEGORY -> resultsDirectory;
            default -> null;
        };
    }

    private String mediaUrl(String category, String fileName) {
        return "/media/" + category + "/" + fileName;
    }

    private void ensureInsideRoot(Path directory) {
        if (!directory.startsWith(storageRoot)) {
            throw new StorageException("Cấu hình storage nằm ngoài thư mục gốc cho phép.");
        }
    }
}
