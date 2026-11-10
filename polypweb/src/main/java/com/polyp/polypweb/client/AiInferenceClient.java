package com.polyp.polypweb.client;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.polyp.polypweb.config.AiServiceProperties;
import com.polyp.polypweb.view.AiHealthView;
import com.polyp.polypweb.view.AiLiveVideoStart;
import com.polyp.polypweb.view.AiPredictionResponse;
import com.polyp.polypweb.view.AiVideoPredictionResponse;
import com.polyp.polypweb.view.ModelHealthView;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;
import tools.jackson.databind.ObjectMapper;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.ConnectException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpConnectTimeoutException;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Component
public class AiInferenceClient {

    private final HttpClient httpClient;
    private final ObjectMapper objectMapper;
    private final String predictUrl;
    private final String healthUrl;
    private final String videoPredictUrl;
    private final String liveUrl;
    private final String videoResultUrl;
    private final Duration readTimeout;
    private final Duration videoReadTimeout;
    private final Duration healthTimeout;

    public AiInferenceClient(
            HttpClient aiHttpClient,
            ObjectMapper objectMapper,
            AiServiceProperties properties) {
        this.httpClient = aiHttpClient;
        this.objectMapper = objectMapper;
        String normalizedBaseUrl = stripTrailingSlash(properties.getBaseUrl().toString());
        this.predictUrl = normalizedBaseUrl + "/predict";
        this.healthUrl = normalizedBaseUrl + "/health";
        this.videoPredictUrl = normalizedBaseUrl + "/video/predict";
        this.liveUrl = normalizedBaseUrl + "/video/live";
        this.videoResultUrl = normalizedBaseUrl + "/video/result";
        this.readTimeout = properties.getReadTimeout();
        this.videoReadTimeout = properties.getVideoReadTimeout() == null
                ? Duration.ofMinutes(10)
                : properties.getVideoReadTimeout();
        this.healthTimeout = properties.getHealthTimeout();
    }

    public void requireModelsAvailable(Collection<String> modelTypes) {
        AiHealthResponse health = readHealth(readTimeout);
        for (String modelType : modelTypes) {
            AiModelHealth modelHealth = health.getModels().get(modelType);
            if (modelHealth == null
                    || !modelHealth.isLoaded()
                    || !"ready".equalsIgnoreCase(modelHealth.getStatus())) {
                throw new AiServiceException(
                        "MODEL_UNAVAILABLE",
                        modelType + " hiện không khả dụng; phiên so sánh chưa được thực hiện."
                );
            }
        }
    }

    public AiHealthView dashboardHealth() {
        AiHealthResponse health = readHealth(healthTimeout);
        List<ModelHealthView> models = List.of(
                dashboardModelHealth(health, "YOLO26s-seg", "Baseline"),
                dashboardModelHealth(health, "YOLO26s-TSVM-FP32-seg", "VMamba")
        );
        String serviceStatus = "ok".equalsIgnoreCase(health.getStatus())
                ? "Hoạt động"
                : "Suy giảm";
        String device = health.getDevice() == null || health.getDevice().isBlank()
                ? "Không xác định"
                : health.getDevice();
        return new AiHealthView(true, serviceStatus, device, models);
    }

    public AiServiceStatus serviceStatus() {
        AiHealthResponse health = readHealth(healthTimeout);
        return new AiServiceStatus(
                isReady(health, "YOLO26s-seg"),
                isReady(health, "YOLO26s-TSVM-FP32-seg")
        );
    }

    public AiPredictionResponse predict(MultipartFile image, String modelType) {
        return predict(image, null, modelType);
    }

    /**
     * Same as {@link #predict(MultipartFile, String)}, optionally sending a ground-truth mask (same size as the
     * image) so FastAPI also returns Dice/IoU/Precision/Recall for this image.
     */
    public AiPredictionResponse predict(MultipartFile image, MultipartFile groundTruth, String modelType) {
        boolean withGroundTruth = groundTruth != null && !groundTruth.isEmpty();
        String boundary = "----PolypVision-" + UUID.randomUUID();
        byte[] requestBody;
        try {
            requestBody = buildMultipartBody(image, withGroundTruth ? groundTruth : null, modelType, boundary);
        } catch (IOException exception) {
            throw new AiServiceException("Không thể đọc tệp ảnh đã tải lên.", exception);
        }

        HttpRequest request = HttpRequest.newBuilder(URI.create(predictUrl))
                .timeout(readTimeout)
                .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofByteArray(requestBody))
                .build();

        HttpResponse<String> response;
        long sentAt = System.nanoTime();
        try {
            response = httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (HttpConnectTimeoutException exception) {
            throw new AiServiceException(
                    "AI_SERVICE_UNAVAILABLE",
                    "Không thể kết nối FastAPI tại cổng 8000. Hãy kiểm tra dịch vụ Python đang chạy.",
                    exception
            );
        } catch (HttpTimeoutException exception) {
            throw new AiServiceException(
                    "AI_SERVICE_TIMEOUT",
                    "FastAPI phản hồi quá thời gian chờ. Vui lòng thử lại.",
                    exception
            );
        } catch (ConnectException exception) {
            throw new AiServiceException(
                    "AI_SERVICE_UNAVAILABLE",
                    "Không thể kết nối FastAPI tại cổng 8000. Hãy kiểm tra dịch vụ Python đang chạy.",
                    exception
            );
        } catch (IOException exception) {
            throw new AiServiceException("Kết nối tới FastAPI bị gián đoạn.", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new AiServiceException("Yêu cầu FastAPI đã bị gián đoạn.", exception);
        }

        double roundTripMs = (System.nanoTime() - sentAt) / 1_000_000.0;

        if (withGroundTruth && (response.statusCode() == 413
                || response.statusCode() == 415
                || response.statusCode() == 422)) {
            throw new AiServiceException(
                    "GROUND_TRUTH_REJECTED",
                    "Mặt nạ thật phải là ảnh JPG/PNG dưới 10 MB, cùng kích thước với ảnh nội soi."
            );
        }
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            String code = response.statusCode() == 503
                    ? "MODEL_UNAVAILABLE"
                    : "AI_SERVICE_UNAVAILABLE";
            throw new AiServiceException(
                    code,
                    "FastAPI từ chối yêu cầu với mã HTTP " + response.statusCode() + "."
            );
        }

        try {
            AiPredictionResponse prediction = objectMapper.readValue(response.body(), AiPredictionResponse.class);
            if (prediction == null || !prediction.isSuccess()) {
                throw new AiServiceException("FastAPI không trả về kết quả inference hợp lệ.");
            }
            if (prediction.getModelType() == null
                    || !prediction.getModelType().equalsIgnoreCase(modelType)) {
                throw new AiServiceException(
                        "MODEL_RESPONSE_MISMATCH",
                        "FastAPI trả về kết quả từ mô hình khác với mô hình đã chọn."
                );
            }
            if (prediction.getResultImageBase64() == null || prediction.getResultImageBase64().isBlank()) {
                throw new AiServiceException("FastAPI không trả về ảnh kết quả phân đoạn.");
            }
            if (!withGroundTruth) {
                prediction.setGroundTruthMetrics(null);
            }
            prediction.setAiRoundTripMs(roundTripMs);
            return prediction;
        } catch (AiServiceException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new AiServiceException("Không thể ánh xạ phản hồi JSON từ FastAPI.", exception);
        }
    }

    /**
     * Offline video analysis on FastAPI. Uses a separate, longer timeout because every sampled frame
     * is segmented; the call blocks until the overlay video is ready.
     */
    public AiVideoPredictionResponse predictVideo(MultipartFile video, String modelType, int sampleFps) {
        VideoUpload upload = videoUpload(video, modelType, sampleFps, true);
        HttpRequest request = HttpRequest.newBuilder(URI.create(videoPredictUrl))
                .timeout(videoReadTimeout)
                .header("Content-Type", "multipart/form-data; boundary=" + upload.boundary())
                .POST(upload.body())
                .build();
        long sentAt = System.nanoTime();
        HttpResponse<String> response = sendVideo(request);
        double roundTripMs = (System.nanoTime() - sentAt) / 1_000_000.0;
        requireVideoAccepted(response);
        return parseVideoPrediction(response.body(), modelType, roundTripMs);
    }

    /**
     * Starts a real-time playback simulation on FastAPI. Returns as soon as the upload is stored; the
     * analysis keeps running there and is followed with {@link #liveVideoStatus} and
     * {@link #openLiveVideoStream}.
     */
    public AiLiveVideoStart startLiveVideo(MultipartFile video, String modelType, int sampleFps) {
        VideoUpload upload = videoUpload(video, modelType, sampleFps, false);
        HttpRequest request = HttpRequest.newBuilder(URI.create(liveUrl))
                .timeout(videoReadTimeout)
                .header("Content-Type", "multipart/form-data; boundary=" + upload.boundary())
                .POST(upload.body())
                .build();
        HttpResponse<String> response = sendVideo(request);
        requireVideoAccepted(response);
        try {
            AiLiveVideoStart start = objectMapper.readValue(response.body(), AiLiveVideoStart.class);
            if (start == null || !validJobId(start.jobId())
                    || start.modelType() == null || !start.modelType().equalsIgnoreCase(modelType)) {
                throw new AiServiceException("MODEL_RESPONSE_MISMATCH",
                        "FastAPI không trả về phiên mô phỏng hợp lệ cho mô hình đã chọn.");
            }
            return start;
        } catch (AiServiceException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new AiServiceException("Không thể ánh xạ phản hồi khởi tạo phiên mô phỏng.", exception);
        }
    }

    /** Progress of a live job: state, frames done, real-time factor, current detection. */
    public Map<String, Object> liveVideoStatus(String jobId) {
        HttpResponse<String> response = sendVideo(liveRequest(jobId, "/status", readTimeout));
        if (response.statusCode() == 404) {
            throw new AiServiceException("LIVE_NOT_FOUND", "Dịch vụ AI không còn giữ phiên mô phỏng này.");
        }
        if (response.statusCode() != 200) {
            throw new AiServiceException("AI_SERVICE_UNAVAILABLE",
                    "FastAPI từ chối yêu cầu trạng thái với mã HTTP " + response.statusCode() + ".");
        }
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> status = objectMapper.readValue(response.body(), Map.class);
            return status;
        } catch (Exception exception) {
            throw new AiServiceException("Không thể đọc trạng thái phiên mô phỏng.", exception);
        }
    }

    /** Opens the MJPEG overlay stream of a live job; the caller must close the body. */
    public HttpResponse<InputStream> openLiveVideoStream(String jobId) {
        HttpRequest request = liveRequest(jobId, "/stream", readTimeout);
        HttpResponse<InputStream> response;
        try {
            response = httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
        } catch (IOException exception) {
            throw new AiServiceException("AI_SERVICE_UNAVAILABLE", "Không mở được luồng hình từ FastAPI.", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new AiServiceException("Yêu cầu FastAPI đã bị gián đoạn.", exception);
        }
        if (response.statusCode() != 200) {
            try {
                response.body().close();
            } catch (IOException ignored) {
                // nothing to release
            }
            throw new AiServiceException(response.statusCode() == 404 ? "LIVE_NOT_FOUND" : "AI_SERVICE_UNAVAILABLE",
                    "FastAPI không cung cấp luồng hình cho phiên này.");
        }
        return response;
    }

    /** Final payload of a finished live job; same shape and checks as {@link #predictVideo}. */
    public AiVideoPredictionResponse liveVideoResult(String jobId, String modelType) {
        long sentAt = System.nanoTime();
        HttpResponse<String> response = sendVideo(liveRequest(jobId, "/result?transfer=file", videoReadTimeout));
        double roundTripMs = (System.nanoTime() - sentAt) / 1_000_000.0;
        if (response.statusCode() == 409) {
            throw new AiServiceException("LIVE_RUNNING", "Phiên mô phỏng vẫn đang chạy.");
        }
        if (response.statusCode() == 404) {
            throw new AiServiceException("LIVE_NOT_FOUND", "Dịch vụ AI không còn giữ phiên mô phỏng này.");
        }
        requireVideoAccepted(response);
        return parseVideoPrediction(response.body(), modelType, roundTripMs);
    }

    /**
     * Opens the one-time download of an overlay video kept by FastAPI (file transfer). The caller must
     * close the stream.
     */
    public InputStream downloadResultVideo(String videoId) {
        if (!validJobId(videoId)) {
            throw new AiServiceException("RESULT_VIDEO_NOT_FOUND", "Mã video kết quả không hợp lệ.");
        }
        HttpRequest request = HttpRequest.newBuilder(URI.create(videoResultUrl + "/" + videoId))
                .timeout(videoReadTimeout)
                .GET()
                .build();
        HttpResponse<InputStream> response;
        try {
            response = httpClient.send(request, HttpResponse.BodyHandlers.ofInputStream());
        } catch (IOException exception) {
            throw new AiServiceException("AI_SERVICE_UNAVAILABLE", "Không tải được video kết quả từ FastAPI.", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new AiServiceException("Yêu cầu FastAPI đã bị gián đoạn.", exception);
        }
        if (response.statusCode() != 200) {
            try {
                response.body().close();
            } catch (IOException ignored) {
                // nothing to release
            }
            throw new AiServiceException(response.statusCode() == 404 ? "RESULT_VIDEO_NOT_FOUND" : "AI_SERVICE_ERROR",
                    "FastAPI không còn giữ video kết quả (HTTP " + response.statusCode() + ").");
        }
        return response.body();
    }

    static boolean validJobId(String jobId) {
        return jobId != null && jobId.matches("[0-9a-f]{32}");
    }

    private HttpRequest liveRequest(String jobId, String suffix, Duration timeout) {
        if (!validJobId(jobId)) {
            throw new AiServiceException("LIVE_NOT_FOUND", "Mã phiên mô phỏng không hợp lệ.");
        }
        return HttpRequest.newBuilder(URI.create(liveUrl + "/" + jobId + suffix))
                .timeout(timeout)
                .GET()
                .build();
    }

    private record VideoUpload(String boundary, HttpRequest.BodyPublisher body) {
    }

    private VideoUpload videoUpload(MultipartFile video, String modelType, int sampleFps, boolean resultAsFile) {
        String boundary = "----PolypVision-" + UUID.randomUUID();
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            String fileName = sanitizeHeaderValue(video.getOriginalFilename(), "uploaded-video.mp4");
            String contentType = video.getContentType();
            if (contentType == null || contentType.isBlank()) {
                contentType = "application/octet-stream";
            }
            writeText(output, "--" + boundary + "\r\n");
            writeText(output, "Content-Disposition: form-data; name=\"video\"; filename=\"" + fileName + "\"\r\n");
            writeText(output, "Content-Type: " + sanitizeHeaderValue(contentType, "application/octet-stream") + "\r\n\r\n");
            byte[] head = output.toByteArray();
            output.reset();
            writeText(output, "\r\n--" + boundary + "\r\n");
            writeText(output, "Content-Disposition: form-data; name=\"modelType\"\r\n\r\n" + modelType + "\r\n");
            writeText(output, "--" + boundary + "\r\n");
            writeText(output, "Content-Disposition: form-data; name=\"sampleFps\"\r\n\r\n" + sampleFps + "\r\n");
            if (resultAsFile) {
                // Long all-frame videos give an overlay video whose Base64 is too large for one JSON string.
                writeText(output, "--" + boundary + "\r\n");
                writeText(output, "Content-Disposition: form-data; name=\"resultVideoTransfer\"\r\n\r\nfile\r\n");
            }
            writeText(output, "--" + boundary + "--\r\n");
            // Stream the (up to 200 MB) video from Spring's temp file instead of copying it into memory.
            video.getInputStream().close();
            HttpRequest.BodyPublisher body = HttpRequest.BodyPublishers.concat(
                    HttpRequest.BodyPublishers.ofByteArray(head),
                    // Known length -> Content-Length header instead of chunked transfer.
                    HttpRequest.BodyPublishers.fromPublisher(
                            HttpRequest.BodyPublishers.ofInputStream(() -> {
                                try {
                                    return video.getInputStream();
                                } catch (IOException exception) {
                                    throw new java.io.UncheckedIOException(exception);
                                }
                            }),
                            video.getSize()
                    ),
                    HttpRequest.BodyPublishers.ofByteArray(output.toByteArray())
            );
            return new VideoUpload(boundary, body);
        } catch (IOException exception) {
            throw new AiServiceException("Không thể đọc tệp video đã tải lên.", exception);
        }
    }

    private HttpResponse<String> sendVideo(HttpRequest request) {
        try {
            return httpClient.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (HttpConnectTimeoutException | ConnectException exception) {
            throw new AiServiceException(
                    "AI_SERVICE_UNAVAILABLE",
                    "Không thể kết nối FastAPI tại cổng 8000. Hãy kiểm tra dịch vụ Python đang chạy.",
                    exception
            );
        } catch (HttpTimeoutException exception) {
            throw new AiServiceException(
                    "AI_SERVICE_TIMEOUT",
                    "FastAPI xử lý video quá thời gian chờ. Hãy thử video ngắn hơn hoặc giảm số khung/giây.",
                    exception
            );
        } catch (IOException exception) {
            throw new AiServiceException("Kết nối tới FastAPI bị gián đoạn.", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new AiServiceException("Yêu cầu FastAPI đã bị gián đoạn.", exception);
        }
    }

    private void requireVideoAccepted(HttpResponse<String> response) {
        int statusCode = response.statusCode();
        if (statusCode == 422 && response.body() != null && response.body().contains("run on a GPU")) {
            throw new AiServiceException(
                    "VIDEO_NEEDS_GPU",
                    "Chế độ phân tích tất cả khung chỉ dùng được khi dịch vụ AI chạy trên GPU. "
                            + "Hãy chọn 2, 5 hoặc 10 khung/giây."
            );
        }
        if (statusCode == 413 || statusCode == 415 || statusCode == 422) {
            throw new AiServiceException(
                    "VIDEO_REJECTED",
                    "Dịch vụ AI không đọc được video này (định dạng, dung lượng hoặc độ dài vượt giới hạn)."
            );
        }
        if (statusCode < 200 || statusCode >= 300) {
            throw new AiServiceException(
                    statusCode == 503 ? "MODEL_UNAVAILABLE" : "AI_SERVICE_UNAVAILABLE",
                    "FastAPI từ chối yêu cầu video với mã HTTP " + statusCode + "."
            );
        }
    }

    private AiVideoPredictionResponse parseVideoPrediction(String body, String modelType, double roundTripMs) {
        try {
            AiVideoPredictionResponse prediction = objectMapper.readValue(body, AiVideoPredictionResponse.class);
            if (prediction == null || !prediction.success()) {
                throw new AiServiceException("FastAPI không trả về kết quả video hợp lệ.");
            }
            if (prediction.modelType() == null || !prediction.modelType().equalsIgnoreCase(modelType)) {
                throw new AiServiceException(
                        "MODEL_RESPONSE_MISMATCH",
                        "FastAPI trả về kết quả từ mô hình khác với mô hình đã chọn."
                );
            }
            if (prediction.resultVideoAsFile() && !validJobId(prediction.resultVideoId())) {
                throw new AiServiceException("FastAPI trả về mã video kết quả không hợp lệ.");
            }
            if (!prediction.resultVideoAsFile()
                    && (prediction.resultVideoBase64() == null || prediction.resultVideoBase64().isBlank())) {
                throw new AiServiceException("FastAPI không trả về video kết quả.");
            }
            return prediction.withAiRoundTripMs(roundTripMs);
        } catch (AiServiceException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new AiServiceException("Không thể ánh xạ phản hồi video từ FastAPI.", exception);
        }
    }

    private byte[] buildMultipartBody(
            MultipartFile image,
            MultipartFile groundTruth,
            String modelType,
            String boundary) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        String fileName = sanitizeHeaderValue(image.getOriginalFilename(), "uploaded-image.jpg");
        String contentType = image.getContentType();
        if (contentType == null || contentType.isBlank()) {
            contentType = "application/octet-stream";
        }

        writeText(output, "--" + boundary + "\r\n");
        writeText(output, "Content-Disposition: form-data; name=\"image\"; filename=\"" + fileName + "\"\r\n");
        writeText(output, "Content-Type: " + contentType + "\r\n\r\n");
        output.write(image.getBytes());
        writeText(output, "\r\n");

        if (groundTruth != null) {
            writeText(output, "--" + boundary + "\r\n");
            writeText(output, "Content-Disposition: form-data; name=\"groundTruth\"; filename=\""
                    + sanitizeHeaderValue(groundTruth.getOriginalFilename(), "mask.png") + "\"\r\n");
            writeText(output, "Content-Type: "
                    + sanitizeHeaderValue(groundTruth.getContentType(), "application/octet-stream") + "\r\n\r\n");
            output.write(groundTruth.getBytes());
            writeText(output, "\r\n");
        }

        writeText(output, "--" + boundary + "\r\n");
        writeText(output, "Content-Disposition: form-data; name=\"modelType\"\r\n\r\n");
        writeText(output, modelType);
        writeText(output, "\r\n--" + boundary + "--\r\n");
        return output.toByteArray();
    }

    private void writeText(ByteArrayOutputStream output, String value) {
        output.writeBytes(value.getBytes(StandardCharsets.UTF_8));
    }

    private String sanitizeHeaderValue(String value, String fallback) {
        if (value == null || value.isBlank()) {
            return fallback;
        }
        return value.replace("\r", "").replace("\n", "").replace("\"", "'");
    }

    private String stripTrailingSlash(String value) {
        return value.endsWith("/") ? value.substring(0, value.length() - 1) : value;
    }

    private AiHealthResponse readHealth(Duration timeout) {
        HttpRequest request = HttpRequest.newBuilder(URI.create(healthUrl))
                .timeout(timeout)
                .GET()
                .build();

        HttpResponse<String> response;
        try {
            response = httpClient.send(
                    request,
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8)
            );
        } catch (HttpConnectTimeoutException | ConnectException exception) {
            throw new AiServiceException(
                    "Không thể kết nối FastAPI để kiểm tra trạng thái mô hình.",
                    exception
            );
        } catch (HttpTimeoutException exception) {
            throw new AiServiceException(
                    "FastAPI phản hồi quá thời gian khi kiểm tra mô hình.",
                    exception
            );
        } catch (IOException exception) {
            throw new AiServiceException("Không thể đọc trạng thái mô hình từ FastAPI.", exception);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new AiServiceException("Yêu cầu kiểm tra mô hình đã bị gián đoạn.", exception);
        }

        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new AiServiceException("FastAPI không sẵn sàng.");
        }
        try {
            return objectMapper.readValue(response.body(), AiHealthResponse.class);
        } catch (Exception exception) {
            throw new AiServiceException("Phản hồi /health của FastAPI không hợp lệ.", exception);
        }
    }

    private ModelHealthView dashboardModelHealth(
            AiHealthResponse health,
            String name,
            String fallbackFamily) {
        AiModelHealth model = health.getModels().get(name);
        if (model == null) {
            return new ModelHealthView(name, fallbackFamily, "Không khả dụng", false);
        }
        boolean ready = model.isLoaded() && "ready".equalsIgnoreCase(model.getStatus());
        String status;
        if (ready) {
            status = "Sẵn sàng";
        } else if (model.getError() != null && !model.getError().isBlank()) {
            status = "Lỗi tải mô hình";
        } else {
            status = "Không khả dụng";
        }
        String family = model.getFamily() == null || model.getFamily().isBlank()
                ? fallbackFamily
                : model.getFamily();
        return new ModelHealthView(name, family, status, ready);
    }

    private boolean isReady(AiHealthResponse health, String modelName) {
        AiModelHealth model = health.getModels().get(modelName);
        return model != null
                && model.isLoaded()
                && "ready".equalsIgnoreCase(model.getStatus());
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private static class AiHealthResponse {

        private String status;
        private String device;
        private Map<String, AiModelHealth> models = Map.of();

        public String getStatus() {
            return status;
        }

        public void setStatus(String status) {
            this.status = status;
        }

        public String getDevice() {
            return device;
        }

        public void setDevice(String device) {
            this.device = device;
        }

        public Map<String, AiModelHealth> getModels() {
            return models;
        }

        public void setModels(Map<String, AiModelHealth> models) {
            this.models = models == null ? Map.of() : models;
        }
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private static class AiModelHealth {

        private String status;
        private boolean loaded;
        private String family;
        private String error;

        public String getStatus() {
            return status;
        }

        public void setStatus(String status) {
            this.status = status;
        }

        public boolean isLoaded() {
            return loaded;
        }

        public void setLoaded(boolean loaded) {
            this.loaded = loaded;
        }

        public String getFamily() {
            return family;
        }

        public void setFamily(String family) {
            this.family = family;
        }

        public String getError() {
            return error;
        }

        public void setError(String error) {
            this.error = error;
        }
    }
}
