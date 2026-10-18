package com.polyp.polypweb.client;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.polyp.polypweb.config.AiServiceProperties;
import com.polyp.polypweb.view.AiHealthView;
import com.polyp.polypweb.view.AiPredictionResponse;
import com.polyp.polypweb.view.ModelHealthView;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;
import tools.jackson.databind.ObjectMapper;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
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
    private final Duration readTimeout;
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
        this.readTimeout = properties.getReadTimeout();
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
        String boundary = "----PolypVision-" + UUID.randomUUID();
        byte[] requestBody;
        try {
            requestBody = buildMultipartBody(image, modelType, boundary);
        } catch (IOException exception) {
            throw new AiServiceException("Không thể đọc tệp ảnh đã tải lên.", exception);
        }

        HttpRequest request = HttpRequest.newBuilder(URI.create(predictUrl))
                .timeout(readTimeout)
                .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                .POST(HttpRequest.BodyPublishers.ofByteArray(requestBody))
                .build();

        HttpResponse<String> response;
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
            return prediction;
        } catch (AiServiceException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new AiServiceException("Không thể ánh xạ phản hồi JSON từ FastAPI.", exception);
        }
    }

    private byte[] buildMultipartBody(
            MultipartFile image,
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
