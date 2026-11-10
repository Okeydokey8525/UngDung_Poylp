package com.polyp.polypweb.controller;

import com.polyp.polypweb.document.VideoAnalysis;
import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DiagnosisModel;
import com.polyp.polypweb.service.VideoAnalysisService;
import com.polyp.polypweb.service.VideoStorageService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import jakarta.servlet.http.HttpServletResponse;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

@Controller
public class VideoController {

    private static final Logger LOGGER = LoggerFactory.getLogger(VideoController.class);
    private static final Map<String, String> MODEL_CODES = Map.of(
            "yolo26s-seg", DiagnosisModel.BASELINE.getModelType(),
            "yolo26s-tsvm-fp32-seg", DiagnosisModel.VMAMBA.getModelType()
    );
    private static final Map<String, MediaType> ORIGINAL_TYPES = Map.of(
            "mp4", MediaType.parseMediaType("video/mp4"),
            "mov", MediaType.parseMediaType("video/quicktime"),
            "avi", MediaType.parseMediaType("video/x-msvideo"),
            "mkv", MediaType.parseMediaType("video/x-matroska"),
            "webm", MediaType.parseMediaType("video/webm")
    );

    private final VideoAnalysisService videoService;
    private final VideoStorageService storageService;

    public VideoController(VideoAnalysisService videoService, VideoStorageService storageService) {
        this.videoService = videoService;
        this.storageService = storageService;
    }

    @GetMapping("/video")
    public String videoPage(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @RequestParam(value = "page", defaultValue = "0") int page,
            Model model) {
        model.addAttribute("pageTitle", "Phân tích video");
        model.addAttribute("activePage", "video");
        model.addAttribute("recentVideos", videoService.recent(principal.getUserId(), page));
        return "video";
    }

    @PostMapping("/video")
    public String analyzeVideo(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @RequestParam(value = "video", required = false) MultipartFile video,
            @RequestParam(value = "modelType", defaultValue = "yolo26s-seg") String modelCode,
            @RequestParam(value = "sampleFps", defaultValue = "5") int sampleFps,
            @RequestParam(value = "analysisMode", defaultValue = "offline") String analysisMode,
            RedirectAttributes redirectAttributes) {
        if (video == null || video.isEmpty()) {
            return warn(redirectAttributes, "Vui lòng chọn một video nội soi trước khi phân tích.");
        }
        String modelType = MODEL_CODES.get(modelCode);
        if (modelType == null) {
            return warn(redirectAttributes, "Chỉ hỗ trợ YOLO26s-seg và YOLO26s-TSVM-FP32-seg.");
        }
        try {
            if ("live".equals(analysisMode)) {
                VideoAnalysisService.LiveSession session =
                        videoService.startLive(video, modelType, sampleFps, principal.getUserId());
                return "redirect:/video/live/" + session.getJobId();
            }
            VideoAnalysis saved = videoService.analyze(video, modelType, sampleFps, principal.getUserId());
            redirectAttributes.addFlashAttribute("flashType", "info");
            redirectAttributes.addFlashAttribute("flashMessage",
                    modelType + " đã phân tích xong " + saved.getFramesProcessed() + " khung hình.");
            return "redirect:/videos/" + saved.getId();
        } catch (DiagnosisOperationException exception) {
            LOGGER.warn("Video analysis rejected modelType={} code={}", modelType, exception.getCode());
            return warn(redirectAttributes, exception.getMessage());
        }
    }

    /** Real-time playback simulation: the overlay stream plays while FastAPI analyses the video. */
    @GetMapping("/video/live/{jobId}")
    public String livePage(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String jobId,
            Model model,
            RedirectAttributes redirectAttributes) {
        Optional<VideoAnalysisService.LiveSession> session =
                videoService.findLive(jobId, principal.getUserId(), principal.isAdmin());
        if (session.isEmpty()) {
            return warn(redirectAttributes, "Không tìm thấy phiên mô phỏng đã yêu cầu.");
        }
        model.addAttribute("pageTitle", "Mô phỏng thời gian thực");
        model.addAttribute("activePage", "video");
        model.addAttribute("live", session.get());
        return "video-live";
    }

    @GetMapping("/video/live/{jobId}/status")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> liveStatus(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String jobId) {
        return videoService.findLive(jobId, principal.getUserId(), principal.isAdmin())
                .map(session -> ResponseEntity.ok()
                        .cacheControl(CacheControl.noStore())
                        .body(videoService.liveStatus(session)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    /**
     * Relays the MJPEG stream from FastAPI. Written synchronously so the request is not cut by the
     * async timeout; it ends with the video or when the browser leaves the page.
     */
    @GetMapping("/video/live/{jobId}/stream")
    public void liveStream(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String jobId,
            HttpServletResponse response) throws IOException {
        Optional<VideoAnalysisService.LiveSession> session =
                videoService.findLive(jobId, principal.getUserId(), principal.isAdmin());
        if (session.isEmpty()) {
            response.sendError(HttpServletResponse.SC_NOT_FOUND);
            return;
        }
        HttpResponse<InputStream> upstream;
        try {
            upstream = videoService.openLiveStream(session.get());
        } catch (com.polyp.polypweb.client.AiServiceException exception) {
            response.sendError(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
            return;
        }
        response.setStatus(HttpServletResponse.SC_OK);
        response.setContentType(upstream.headers().firstValue("Content-Type")
                .orElse("multipart/x-mixed-replace; boundary=polypframe"));
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("X-Accel-Buffering", "no");
        byte[] buffer = new byte[64 * 1024];
        try (InputStream input = upstream.body()) {
            OutputStream output = response.getOutputStream();
            int read;
            while ((read = input.read(buffer)) >= 0) {
                output.write(buffer, 0, read);
                output.flush();
            }
        } catch (IOException exception) {
            // The browser left the page or FastAPI ended the stream; the analysis keeps running.
            LOGGER.debug("Live stream closed jobId={}", jobId);
        }
    }

    @GetMapping("/videos/{id}")
    public String videoResult(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id,
            Model model,
            RedirectAttributes redirectAttributes) {
        Optional<VideoAnalysis> analysis = videoService.findAccessible(id, principal.getUserId(), principal.isAdmin());
        if (analysis.isEmpty()) {
            return warn(redirectAttributes, "Không tìm thấy kết quả video đã yêu cầu.");
        }
        model.addAttribute("pageTitle", "Kết quả phân tích video");
        model.addAttribute("activePage", "video");
        model.addAttribute("analysis", analysis.get());
        model.addAttribute("vmambaModel", DiagnosisModel.VMAMBA.getModelType().equals(analysis.get().getModelType()));
        return "video-result";
    }

    @GetMapping("/videos/{id}/result-video")
    public ResponseEntity<Resource> resultVideo(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return videoService.findAccessible(id, principal.getUserId(), principal.isAdmin())
                .flatMap(analysis -> storageService.loadResult(analysis.getResultVideoFile()))
                .map(resource -> media(resource, resultType(resource.getFilename())))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @GetMapping("/videos/{id}/original-video")
    public ResponseEntity<Resource> originalVideo(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return videoService.findAccessible(id, principal.getUserId(), principal.isAdmin())
                .flatMap(analysis -> storageService.loadOriginal(analysis.getOriginalVideoFile())
                        .map(resource -> media(resource, originalType(analysis.getOriginalVideoFile()))))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping("/videos/{id}/delete")
    public String deleteVideo(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id,
            RedirectAttributes redirectAttributes) {
        boolean deleted = videoService.delete(id, principal.getUserId(), principal.isAdmin());
        redirectAttributes.addFlashAttribute("flashType", deleted ? "info" : "warning");
        redirectAttributes.addFlashAttribute("flashMessage",
                deleted ? "Đã xóa kết quả video và các tệp liên quan." : "Không tìm thấy kết quả video để xóa.");
        return "redirect:/video";
    }

    public static MediaType resultType(String fileName) {
        return fileName != null && fileName.endsWith(".mp4")
                ? MediaType.parseMediaType("video/mp4")
                : MediaType.parseMediaType("video/webm");
    }

    private ResponseEntity<Resource> media(Resource resource, MediaType type) {
        // Returning a Resource lets Spring MVC answer HTTP Range requests, which browsers use to seek video.
        return ResponseEntity.ok()
                .contentType(type)
                .cacheControl(CacheControl.maxAge(Duration.ofHours(1)).cachePrivate())
                .body(resource);
    }

    private MediaType originalType(String fileName) {
        String extension = fileName == null ? "" : fileName.substring(fileName.lastIndexOf('.') + 1);
        return ORIGINAL_TYPES.getOrDefault(extension.toLowerCase(Locale.ROOT), MediaType.APPLICATION_OCTET_STREAM);
    }

    private String warn(RedirectAttributes redirectAttributes, String message) {
        redirectAttributes.addFlashAttribute("flashType", "warning");
        redirectAttributes.addFlashAttribute("flashMessage", message);
        return "redirect:/video";
    }
}
