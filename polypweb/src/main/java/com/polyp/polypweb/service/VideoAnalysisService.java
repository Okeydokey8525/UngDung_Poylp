package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.document.VideoAnalysis;
import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.repository.VideoAnalysisRepository;
import com.polyp.polypweb.view.AiLiveVideoStart;
import com.polyp.polypweb.view.AiVideoPredictionResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Upload validation, FastAPI call, storage and history for video analysis: offline (wait for the
 * result) or as a real-time playback simulation (watch while FastAPI analyses, saved when it ends).
 */
@Service
public class VideoAnalysisService {

    public static final long MAX_VIDEO_BYTES = 200L * 1024 * 1024;
    /** 0 = analyse every frame (needs the AI service on a GPU). */
    public static final int ALL_FRAMES = 0;
    public static final Set<Integer> SAMPLE_FPS_CHOICES = Set.of(ALL_FRAMES, 2, 5, 10);
    private static final Set<String> ALLOWED_EXTENSIONS = Set.of("mp4", "avi", "mov", "mkv", "webm");
    private static final Logger LOGGER = LoggerFactory.getLogger(VideoAnalysisService.class);

    private final VideoAnalysisRepository repository;
    private final AiInferenceClient aiInferenceClient;
    private final VideoStorageService storageService;
    private final Map<String, LiveSession> liveSessions = new ConcurrentHashMap<>();
    private static final Duration LIVE_SESSION_TTL = Duration.ofHours(2);

    /** A real-time playback simulation started by one user; its result is saved once. */
    public static final class LiveSession {
        private final String jobId;
        private final String userId;
        private final DiagnosisModel model;
        private final String fileName;
        private final UUID storageId;
        private final String originalFile;
        private final long originalSizeBytes;
        private final int requestedSampleFps;
        private final LocalDateTime createdAt = LocalDateTime.now();
        private String savedVideoId;
        private String error;

        LiveSession(String jobId, String userId, DiagnosisModel model, String fileName, UUID storageId,
                    String originalFile, long originalSizeBytes, int requestedSampleFps) {
            this.jobId = jobId;
            this.userId = userId;
            this.model = model;
            this.fileName = fileName;
            this.storageId = storageId;
            this.originalFile = originalFile;
            this.originalSizeBytes = originalSizeBytes;
            this.requestedSampleFps = requestedSampleFps;
        }

        public String getJobId() {
            return jobId;
        }

        public String getModelType() {
            return model.getModelType();
        }

        public boolean isVmamba() {
            return model == DiagnosisModel.VMAMBA;
        }

        public String getFileName() {
            return fileName;
        }

        public int getRequestedSampleFps() {
            return requestedSampleFps;
        }

        public synchronized String getSavedVideoId() {
            return savedVideoId;
        }

        public synchronized String getError() {
            return error;
        }
    }

    public VideoAnalysisService(
            VideoAnalysisRepository repository,
            AiInferenceClient aiInferenceClient,
            VideoStorageService storageService) {
        this.repository = repository;
        this.aiInferenceClient = aiInferenceClient;
        this.storageService = storageService;
    }

    public VideoAnalysis analyze(MultipartFile video, String requestedModelType, int sampleFps, String userId) {
        DiagnosisModel model = DiagnosisModel.fromModelType(requestedModelType)
                .orElseThrow(() -> rejected(HttpStatus.BAD_REQUEST, "INVALID_MODEL",
                        "Mô hình được chọn không được hỗ trợ."));
        if (!SAMPLE_FPS_CHOICES.contains(sampleFps)) {
            throw rejected(HttpStatus.BAD_REQUEST, "INVALID_SAMPLE_FPS", "Tốc độ lấy mẫu phải là 2, 5, 10 khung/giây hoặc tất cả khung.");
        }
        String extension = validateUpload(video);
        String fileName = safeFileName(video.getOriginalFilename());

        UUID storageId = UUID.randomUUID();
        String originalFile = null;
        String resultFile = null;
        try {
            originalFile = storageService.storeOriginal(video, storageId, extension);
            AiVideoPredictionResponse prediction = aiInferenceClient.predictVideo(
                    video, model.getModelType(), sampleFps);
            resultFile = storeResultVideo(prediction, storageId);

            return repository.save(toAnalysis(prediction, model, userId, fileName, originalFile, resultFile,
                    video.getSize()));
        } catch (AiServiceException exception) {
            storageService.deleteQuietly(originalFile, resultFile);
            throw mapAiFailure(exception);
        } catch (StorageException exception) {
            storageService.deleteQuietly(originalFile, resultFile);
            throw new DiagnosisOperationException(HttpStatus.INTERNAL_SERVER_ERROR, "STORAGE_FAILURE",
                    "Không thể lưu video. Dữ liệu tạm đã được dọn dẹp.", exception);
        } catch (RuntimeException exception) {
            storageService.deleteQuietly(originalFile, resultFile);
            LOGGER.error("Video analysis save failure modelType={} type={}",
                    model.getModelType(), exception.getClass().getSimpleName());
            throw new DiagnosisOperationException(HttpStatus.INTERNAL_SERVER_ERROR, "VIDEO_SAVE_FAILED",
                    "Không thể lưu kết quả phân tích video. Dữ liệu tạm đã được dọn dẹp.", exception);
        }
    }

    private static VideoAnalysis toAnalysis(AiVideoPredictionResponse prediction, DiagnosisModel model,
                                            String userId, String fileName, String originalFile,
                                            String resultFile, long originalSizeBytes) {
        VideoAnalysis analysis = new VideoAnalysis();
        analysis.setUserId(userId);
        analysis.setFileName(fileName);
        analysis.setModelType(model.getModelType());
        analysis.setSampleFps(prediction.sampleFps());
        analysis.setRequestedSampleFps(prediction.requestedSampleFps());
        analysis.setSampleRateReduced(prediction.sampleRateReduced());
        analysis.setOutputFps(prediction.outputFps() == null ? 0 : prediction.outputFps());
        analysis.setFramesHeld(prediction.framesHeld() == null ? 0 : prediction.framesHeld());
        analysis.setSourceFps(prediction.sourceFps());
        analysis.setSourceFrameCount(prediction.sourceFrameCount());
        analysis.setDurationSec(prediction.durationSec());
        analysis.setWidth(prediction.width());
        analysis.setHeight(prediction.height());
        analysis.setFramesProcessed(prediction.framesProcessed());
        analysis.setFramesWithPolyp(prediction.framesWithPolyp());
        analysis.setMaxConfidence(prediction.maxConfidence());
        analysis.setProcessingTimeMs(prediction.processingTimeMs());
        analysis.setAverageInferenceMs(prediction.averageInferenceMs());
        analysis.setThroughputFps(prediction.throughputFps());
        analysis.setAiRoundTripMs(prediction.aiRoundTripMs());
        analysis.setTimeline(prediction.timeline());
        analysis.setSegments(prediction.segments());
        analysis.setOriginalVideoFile(originalFile);
        analysis.setResultVideoFile(resultFile);
        analysis.setOriginalSizeBytes(originalSizeBytes);
        analysis.setCreatedAt(LocalDateTime.now());
        return analysis;
    }

    /**
     * Starts a real-time playback simulation: the upload is validated and stored like an offline run,
     * then FastAPI analyses it in the background while the browser watches the stream.
     */
    public LiveSession startLive(MultipartFile video, String requestedModelType, int sampleFps, String userId) {
        DiagnosisModel model = DiagnosisModel.fromModelType(requestedModelType)
                .orElseThrow(() -> rejected(HttpStatus.BAD_REQUEST, "INVALID_MODEL",
                        "Mô hình được chọn không được hỗ trợ."));
        if (!SAMPLE_FPS_CHOICES.contains(sampleFps)) {
            throw rejected(HttpStatus.BAD_REQUEST, "INVALID_SAMPLE_FPS", "Tốc độ lấy mẫu phải là 2, 5, 10 khung/giây hoặc tất cả khung.");
        }
        String extension = validateUpload(video);
        String fileName = safeFileName(video.getOriginalFilename());
        evictOldLiveSessions();

        UUID storageId = UUID.randomUUID();
        String originalFile = null;
        try {
            originalFile = storageService.storeOriginal(video, storageId, extension);
            AiLiveVideoStart start = aiInferenceClient.startLiveVideo(video, model.getModelType(), sampleFps);
            LiveSession session = new LiveSession(start.jobId(), userId, model, fileName, storageId,
                    originalFile, video.getSize(), sampleFps);
            liveSessions.put(start.jobId(), session);
            return session;
        } catch (AiServiceException exception) {
            storageService.deleteQuietly(originalFile, null);
            throw mapAiFailure(exception);
        } catch (StorageException exception) {
            storageService.deleteQuietly(originalFile, null);
            throw new DiagnosisOperationException(HttpStatus.INTERNAL_SERVER_ERROR, "STORAGE_FAILURE",
                    "Không thể lưu video. Dữ liệu tạm đã được dọn dẹp.", exception);
        }
    }

    /** Opens the MJPEG overlay stream of the session on FastAPI; the caller closes the body. */
    public java.net.http.HttpResponse<InputStream> openLiveStream(LiveSession session) {
        return aiInferenceClient.openLiveVideoStream(session.jobId);
    }

    /** The live session if it exists and belongs to the user (admins see all). */
    public Optional<LiveSession> findLive(String jobId, String userId, boolean admin) {
        LiveSession session = jobId == null ? null : liveSessions.get(jobId);
        if (session == null || !(admin || session.userId.equals(userId))) {
            return Optional.empty();
        }
        return Optional.of(session);
    }

    /**
     * Progress for the live page. When FastAPI reports "done" the result is fetched, stored and saved
     * to history exactly once, and {@code savedVideoId} is added so the page can open the result.
     */
    public Map<String, Object> liveStatus(LiveSession session) {
        Map<String, Object> status = new LinkedHashMap<>();
        synchronized (session) {
            if (session.savedVideoId != null || session.error != null) {
                status.put("state", session.savedVideoId != null ? "saved" : "error");
                status.put("savedVideoId", session.savedVideoId);
                status.put("error", session.error);
                return status;
            }
            try {
                status.putAll(aiInferenceClient.liveVideoStatus(session.jobId));
            } catch (AiServiceException exception) {
                fail(session, exception.getCode().equals("LIVE_NOT_FOUND")
                        ? "Dịch vụ AI đã khởi động lại hoặc không còn giữ phiên này."
                        : "Không kết nối được dịch vụ AI để theo dõi phiên.");
                status.put("state", "error");
                status.put("error", session.error);
                return status;
            }
            Object state = status.get("state");
            if ("done".equals(state)) {
                saveLiveResult(session);
            } else if ("error".equals(state)) {
                fail(session, "Dịch vụ AI không phân tích được video này (định dạng, độ dài hoặc số khung vượt giới hạn).");
            }
            status.put("state", session.savedVideoId != null ? "saved" : session.error != null ? "error" : state);
            status.put("savedVideoId", session.savedVideoId);
            status.put("error", session.error);
            return status;
        }
    }

    private void saveLiveResult(LiveSession session) {
        String resultFile = null;
        try {
            AiVideoPredictionResponse prediction =
                    aiInferenceClient.liveVideoResult(session.jobId, session.model.getModelType());
            resultFile = storeResultVideo(prediction, session.storageId);
            VideoAnalysis saved = repository.save(toAnalysis(prediction, session.model, session.userId,
                    session.fileName, session.originalFile, resultFile, session.originalSizeBytes));
            session.savedVideoId = saved.getId();
        } catch (RuntimeException exception) {
            storageService.deleteQuietly(null, resultFile);
            LOGGER.error("Live video save failure modelType={} type={} message={}",
                    session.model.getModelType(), exception.getClass().getSimpleName(), exception.getMessage());
            fail(session, "Không thể lưu kết quả mô phỏng. Dữ liệu tạm đã được dọn dẹp.");
        }
    }

    /** Stores the overlay video, downloading it as a file when FastAPI did not inline it as Base64. */
    private String storeResultVideo(AiVideoPredictionResponse prediction, UUID storageId) {
        if (prediction.resultVideoAsFile()) {
            return storageService.storeResult(aiInferenceClient.downloadResultVideo(prediction.resultVideoId()),
                    storageId);
        }
        return storageService.storeResult(prediction.resultVideoBase64(), storageId);
    }

    private void fail(LiveSession session, String message) {
        session.error = message;
        storageService.deleteQuietly(session.originalFile, null);
    }

    private void evictOldLiveSessions() {
        LocalDateTime cutoff = LocalDateTime.now().minus(LIVE_SESSION_TTL);
        liveSessions.values().removeIf(session -> session.createdAt.isBefore(cutoff));
    }

    public Optional<VideoAnalysis> findAccessible(String id, String userId, boolean admin) {
        if (id == null || id.isBlank()) {
            return Optional.empty();
        }
        return admin ? repository.findById(id) : repository.findByIdAndUserId(id, userId);
    }

    public Page<VideoAnalysis> recent(String userId, int page) {
        return repository.findAllByUserIdOrderByCreatedAtDesc(userId, PageRequest.of(Math.max(0, page), 10));
    }

    public boolean delete(String id, String userId, boolean admin) {
        Optional<VideoAnalysis> analysis = findAccessible(id, userId, admin);
        if (analysis.isEmpty()) {
            return false;
        }
        repository.delete(analysis.get());
        storageService.deleteQuietly(analysis.get().getOriginalVideoFile(), analysis.get().getResultVideoFile());
        return true;
    }

    /** Checks size, extension, MIME type and the container signature; returns the lower-case extension. */
    String validateUpload(MultipartFile video) {
        if (video == null || video.isEmpty()) {
            throw rejected(HttpStatus.BAD_REQUEST, "EMPTY_FILE", "Vui lòng chọn một video.");
        }
        if (video.getSize() > MAX_VIDEO_BYTES) {
            throw rejected(HttpStatus.PAYLOAD_TOO_LARGE, "FILE_TOO_LARGE", "Video vượt quá 200 MB.");
        }
        String name = video.getOriginalFilename() == null ? "" : video.getOriginalFilename();
        int dot = name.lastIndexOf('.');
        String extension = dot < 0 ? "" : name.substring(dot + 1).toLowerCase(Locale.ROOT);
        String contentType = video.getContentType() == null ? "" : video.getContentType().toLowerCase(Locale.ROOT);
        if (!ALLOWED_EXTENSIONS.contains(extension)
                || !(contentType.startsWith("video/") || contentType.equals("application/octet-stream"))) {
            throw rejected(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "UNSUPPORTED_TYPE",
                    "Chỉ hỗ trợ video MP4, AVI, MOV, MKV hoặc WEBM.");
        }
        byte[] header = new byte[12];
        int read;
        try (InputStream input = video.getInputStream()) {
            read = input.readNBytes(header, 0, header.length);
        } catch (IOException exception) {
            throw rejected(HttpStatus.BAD_REQUEST, "UNREADABLE_FILE", "Không thể đọc video tải lên.");
        }
        if (!signatureMatches(extension, header, read)) {
            throw rejected(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "SIGNATURE_MISMATCH",
                    "Nội dung tệp không khớp định dạng video đã khai báo.");
        }
        return extension;
    }

    static boolean signatureMatches(String extension, byte[] header, int length) {
        if (length < 12) {
            return false;
        }
        return switch (extension) {
            case "mp4", "mov" -> header[4] == 'f' && header[5] == 't' && header[6] == 'y' && header[7] == 'p';
            case "avi" -> header[0] == 'R' && header[1] == 'I' && header[2] == 'F' && header[3] == 'F'
                    && header[8] == 'A' && header[9] == 'V' && header[10] == 'I';
            case "mkv", "webm" -> VideoStorageService.isWebm(header);
            default -> false;
        };
    }

    private String safeFileName(String original) {
        if (original == null || original.isBlank()) {
            return "video";
        }
        String name = original.replace('\\', '/');
        name = name.substring(name.lastIndexOf('/') + 1).replaceAll("[\\r\\n\\t]", " ").strip();
        return name.length() > 120 ? name.substring(0, 120) : name;
    }

    private DiagnosisOperationException mapAiFailure(AiServiceException exception) {
        return switch (exception.getCode()) {
            case "VIDEO_REJECTED" -> new DiagnosisOperationException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "VIDEO_REJECTED", exception.getMessage(), exception);
            case "VIDEO_NEEDS_GPU" -> new DiagnosisOperationException(HttpStatus.UNPROCESSABLE_ENTITY,
                    "VIDEO_NEEDS_GPU", exception.getMessage(), exception);
            case "MODEL_UNAVAILABLE" -> new DiagnosisOperationException(HttpStatus.SERVICE_UNAVAILABLE,
                    "MODEL_UNAVAILABLE", "Mô hình được chọn hiện không khả dụng.", exception);
            case "AI_SERVICE_TIMEOUT" -> new DiagnosisOperationException(HttpStatus.GATEWAY_TIMEOUT,
                    "AI_SERVICE_TIMEOUT", exception.getMessage(), exception);
            case "MODEL_RESPONSE_MISMATCH" -> new DiagnosisOperationException(HttpStatus.BAD_GATEWAY,
                    "MODEL_RESPONSE_MISMATCH", "Dịch vụ AI trả về kết quả từ mô hình không đúng yêu cầu.", exception);
            default -> new DiagnosisOperationException(HttpStatus.SERVICE_UNAVAILABLE,
                    "AI_SERVICE_UNAVAILABLE", "Dịch vụ AI hiện không khả dụng. Vui lòng thử lại sau.", exception);
        };
    }

    private DiagnosisOperationException rejected(HttpStatus status, String code, String message) {
        return new DiagnosisOperationException(status, code, message);
    }
}
