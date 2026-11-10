package com.polyp.polypweb.service;

import com.polyp.polypweb.config.StorageProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.Resource;
import org.springframework.core.io.UrlResource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Base64;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Pattern;

/**
 * Local storage for uploaded videos and overlay videos, kept apart from the image storage.
 * MongoDB stores only the generated file names; files are served after an ownership check.
 */
@Service
public class VideoStorageService {

    public static final long MAX_RESULT_BYTES = 400L * 1024 * 1024;
    private static final Set<String> ORIGINAL_EXTENSIONS = Set.of("mp4", "avi", "mov", "mkv", "webm");
    private static final Pattern ORIGINAL_NAME = Pattern.compile(
            "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\.(mp4|avi|mov|mkv|webm)$");
    private static final Pattern RESULT_NAME = Pattern.compile(
            "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_result\\.(webm|mp4)$");

    private final Path originalDirectory;
    private final Path resultsDirectory;

    @Autowired
    public VideoStorageService(StorageProperties properties) {
        this(properties.getRoot());
    }

    public VideoStorageService(Path configuredRoot) {
        Path root = configuredRoot.isAbsolute()
                ? configuredRoot
                : Path.of(System.getProperty("user.dir")).resolve(configuredRoot);
        Path videos = root.toAbsolutePath().normalize().resolve("videos");
        this.originalDirectory = videos.resolve("original");
        this.resultsDirectory = videos.resolve("results");
        try {
            Files.createDirectories(originalDirectory);
            Files.createDirectories(resultsDirectory);
        } catch (IOException exception) {
            // Health and the first upload report the problem; startup must not fail on storage permissions.
        }
    }

    /** Stores the upload as {@code <uuid>.<ext>} and returns the generated file name. */
    public String storeOriginal(MultipartFile video, UUID storageId, String extension) {
        if (!ORIGINAL_EXTENSIONS.contains(extension)) {
            throw new StorageException("Định dạng video không được hỗ trợ.");
        }
        String fileName = storageId + "." + extension;
        try (InputStream input = video.getInputStream()) {
            write(originalDirectory, fileName, input.readAllBytes());
        } catch (IOException exception) {
            throw new StorageException("Không thể đọc video tải lên.", exception);
        }
        return fileName;
    }

    /**
     * Decodes the overlay video returned by FastAPI and stores it as {@code <uuid>_result.mp4} (H.264) or
     * {@code <uuid>_result.webm} (VP8). The container is taken from the file signature, not from the client.
     */
    public String storeResult(String resultVideoBase64, UUID storageId) {
        byte[] content;
        try {
            content = Base64.getDecoder().decode(resultVideoBase64 == null ? "" : resultVideoBase64);
        } catch (IllegalArgumentException exception) {
            throw new StorageException("Video kết quả Base64 không hợp lệ.", exception);
        }
        if (content.length < 8 || content.length > MAX_RESULT_BYTES || !(isWebm(content) || isMp4(content))) {
            throw new StorageException("Video kết quả không phải MP4 hoặc WebM hợp lệ.");
        }
        String fileName = storageId + (isMp4(content) ? "_result.mp4" : "_result.webm");
        write(resultsDirectory, fileName, content);
        return fileName;
    }

    /**
     * Streams an overlay video downloaded from FastAPI to {@code <uuid>_result.mp4|webm} without holding
     * it in memory. The container is taken from the first bytes; the size is capped at
     * {@link #MAX_RESULT_BYTES}.
     */
    public String storeResult(InputStream input, UUID storageId) {
        Path temporary = null;
        try (InputStream source = input) {
            byte[] head = source.readNBytes(8);
            if (head.length < 8 || !(isWebm(head) || isMp4(head))) {
                throw new StorageException("Video kết quả không phải MP4 hoặc WebM hợp lệ.");
            }
            String fileName = storageId + (isMp4(head) ? "_result.mp4" : "_result.webm");
            Path target = resultsDirectory.resolve(fileName).normalize();
            if (!target.startsWith(resultsDirectory)) {
                throw new StorageException("Đường dẫn lưu video không hợp lệ.");
            }
            Files.createDirectories(resultsDirectory);
            temporary = Files.createTempFile(resultsDirectory, fileName, ".tmp");
            long written = head.length;
            try (OutputStream output = Files.newOutputStream(temporary)) {
                output.write(head);
                byte[] buffer = new byte[1 << 16];
                int read;
                while ((read = source.read(buffer)) != -1) {
                    written += read;
                    if (written > MAX_RESULT_BYTES) {
                        throw new StorageException("Video kết quả vượt quá "
                                + (MAX_RESULT_BYTES / (1024 * 1024)) + " MB.");
                    }
                    output.write(buffer, 0, read);
                }
            }
            try {
                Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException exception) {
                Files.move(temporary, target);
            }
            temporary = null;
            return fileName;
        } catch (IOException exception) {
            throw new StorageException("Không thể lưu video kết quả vào storage.", exception);
        } finally {
            if (temporary != null) {
                try {
                    Files.deleteIfExists(temporary);
                } catch (IOException ignored) {
                    // best effort
                }
            }
        }
    }

    public Optional<Resource> loadOriginal(String fileName) {
        return load(originalDirectory, fileName, ORIGINAL_NAME);
    }

    public Optional<Resource> loadResult(String fileName) {
        return load(resultsDirectory, fileName, RESULT_NAME);
    }

    public void deleteQuietly(String originalFile, String resultFile) {
        deleteQuietly(originalDirectory, originalFile, ORIGINAL_NAME);
        deleteQuietly(resultsDirectory, resultFile, RESULT_NAME);
    }

    /** ISO base media file: a box whose type at bytes 4..7 is {@code ftyp}. */
    static boolean isMp4(byte[] content) {
        return content.length >= 8
                && content[4] == 'f' && content[5] == 't' && content[6] == 'y' && content[7] == 'p';
    }

    static boolean isWebm(byte[] content) {
        return content.length >= 4
                && (content[0] & 0xff) == 0x1a
                && (content[1] & 0xff) == 0x45
                && (content[2] & 0xff) == 0xdf
                && (content[3] & 0xff) == 0xa3;
    }

    private Optional<Resource> load(Path directory, String fileName, Pattern allowed) {
        if (fileName == null || !allowed.matcher(fileName).matches()) {
            return Optional.empty();
        }
        Path file = directory.resolve(fileName).normalize();
        if (!file.startsWith(directory) || !Files.isRegularFile(file) || !Files.isReadable(file)) {
            return Optional.empty();
        }
        try {
            return Optional.of(new UrlResource(file.toUri()));
        } catch (IOException exception) {
            return Optional.empty();
        }
    }

    private void deleteQuietly(Path directory, String fileName, Pattern allowed) {
        if (fileName == null || !allowed.matcher(fileName).matches()) {
            return;
        }
        try {
            Files.deleteIfExists(directory.resolve(fileName).normalize());
        } catch (IOException exception) {
            // Best effort cleanup; the record is already gone or being rolled back.
        }
    }

    private void write(Path directory, String fileName, byte[] content) {
        Path target = directory.resolve(fileName).normalize();
        if (!target.startsWith(directory)) {
            throw new StorageException("Đường dẫn lưu video không hợp lệ.");
        }
        Path temporary = null;
        try {
            Files.createDirectories(directory);
            temporary = Files.createTempFile(directory, fileName, ".tmp");
            Files.write(temporary, content);
            try {
                Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException exception) {
                Files.move(temporary, target);
            }
        } catch (IOException exception) {
            if (temporary != null) {
                try {
                    Files.deleteIfExists(temporary);
                } catch (IOException cleanup) {
                    exception.addSuppressed(cleanup);
                }
            }
            throw new StorageException("Không thể lưu video vào storage.", exception);
        }
    }
}
