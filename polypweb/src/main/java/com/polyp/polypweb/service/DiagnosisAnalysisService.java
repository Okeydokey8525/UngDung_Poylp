package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.view.AiPredictionResponse;
import com.polyp.polypweb.view.DiagnosisResultView;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.time.LocalDateTime;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

@Service
public class DiagnosisAnalysisService {

    private static final Logger LOGGER = LoggerFactory.getLogger(DiagnosisAnalysisService.class);
    private static final long MAX_UPLOAD_BYTES = 10L * 1024 * 1024;
    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of("image/jpeg", "image/png");
    private static final Set<String> ALLOWED_EXTENSIONS = Set.of("jpg", "jpeg", "png");

    private final DiagnosisHistoryService historyService;
    private final AiInferenceClient aiInferenceClient;
    private final FileStorageService storageService;

    public DiagnosisAnalysisService(
            DiagnosisHistoryService historyService,
            AiInferenceClient aiInferenceClient,
            FileStorageService storageService) {
        this.historyService = historyService;
        this.aiInferenceClient = aiInferenceClient;
        this.storageService = storageService;
    }

    public DiagnosisResultView analyze(
            MultipartFile image,
            String requestedModelType,
            String userId) {
        DiagnosisModel model = DiagnosisModel.fromModelType(requestedModelType)
                .orElseThrow(() -> new DiagnosisOperationException(
                        HttpStatus.BAD_REQUEST,
                        "INVALID_MODEL",
                        "Mô hình được chọn không được hỗ trợ."
                ));
        String safeFileName = validateUpload(image);
        UUID storageId = UUID.randomUUID();
        String originalImageUrl = null;
        String resultImageUrl = null;

        try {
            originalImageUrl = storageService.storeOriginal(image, storageId);
            AiPredictionResponse prediction = aiInferenceClient.predict(
                    image,
                    model.getModelType()
            );
            if (!model.getModelType().equals(prediction.getModelType())) {
                throw new DiagnosisOperationException(
                        HttpStatus.BAD_GATEWAY,
                        "MODEL_RESPONSE_MISMATCH",
                        "Dịch vụ AI trả về kết quả từ mô hình không đúng yêu cầu."
                );
            }
            resultImageUrl = storageService.storeResult(
                    prediction.getResultImageBase64(),
                    storageId
            );
            DiagnosisResultView result = toResult(
                    prediction,
                    safeFileName,
                    model,
                    originalImageUrl,
                    resultImageUrl
            );
            return historyService.saveResult(result, userId);
        } catch (DiagnosisOperationException exception) {
            rollback(originalImageUrl, resultImageUrl);
            throw exception;
        } catch (AiServiceException exception) {
            rollback(originalImageUrl, resultImageUrl);
            throw mapAiFailure(exception);
        } catch (StorageException exception) {
            rollback(originalImageUrl, resultImageUrl);
            LOGGER.warn(
                    "Diagnosis storage failure userId={} modelType={} type={}",
                    shortId(userId),
                    model.getModelType(),
                    exception.getClass().getSimpleName()
            );
            throw new DiagnosisOperationException(
                    HttpStatus.INTERNAL_SERVER_ERROR,
                    "STORAGE_FAILURE",
                    "Không thể lưu ảnh phân tích. Dữ liệu tạm đã được dọn dẹp.",
                    exception
            );
        } catch (RuntimeException exception) {
            rollback(originalImageUrl, resultImageUrl);
            LOGGER.error(
                    "Diagnosis persistence failure userId={} modelType={} type={}",
                    shortId(userId),
                    model.getModelType(),
                    exception.getClass().getSimpleName()
            );
            throw new DiagnosisOperationException(
                    HttpStatus.INTERNAL_SERVER_ERROR,
                    "DIAGNOSIS_SAVE_FAILED",
                    "Không thể lưu kết quả phân tích. Dữ liệu tạm đã được rollback.",
                    exception
            );
        }
    }

    private String validateUpload(MultipartFile image) {
        try {
            return ImageUploadValidator.validate(image, storageService);
        } catch (com.polyp.polypweb.exception.UploadValidationException exception) {
            throw new DiagnosisOperationException(
                    exception.getStatus(),
                    exception.getCode(),
                    exception.getMessage(),
                    exception
            );
        }
    }

    private DiagnosisResultView toResult(
            AiPredictionResponse prediction,
            String fileName,
            DiagnosisModel model,
            String originalImageUrl,
            String resultImageUrl) {
        double confidence = prediction.getConfidence() <= 1
                ? prediction.getConfidence() * 100
                : prediction.getConfidence();
        confidence = Double.isFinite(confidence)
                ? Math.max(0, Math.min(100, confidence))
                : 0;
        double processingTime = Double.isFinite(prediction.getProcessingTimeMs())
                ? Math.max(0, prediction.getProcessingTimeMs())
                : 0;
        return new DiagnosisResultView(
                null,
                originalImageUrl,
                resultImageUrl,
                fileName,
                model.getModelType(),
                prediction.isDetected(),
                prediction.getLabel(),
                confidence,
                processingTime,
                Math.max(0, prediction.getMaskCount()),
                "",
                LocalDateTime.now(),
                false,
                null,
                false
        );
    }

    private DiagnosisOperationException mapAiFailure(AiServiceException exception) {
        return switch (exception.getCode()) {
            case "MODEL_UNAVAILABLE" -> new DiagnosisOperationException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "MODEL_UNAVAILABLE",
                    "Mô hình được chọn hiện không khả dụng.",
                    exception
            );
            case "AI_SERVICE_TIMEOUT" -> new DiagnosisOperationException(
                    HttpStatus.GATEWAY_TIMEOUT,
                    "AI_SERVICE_TIMEOUT",
                    "Dịch vụ AI phản hồi quá thời gian.",
                    exception
            );
            case "MODEL_RESPONSE_MISMATCH" -> new DiagnosisOperationException(
                    HttpStatus.BAD_GATEWAY,
                    "MODEL_RESPONSE_MISMATCH",
                    "Dịch vụ AI trả về kết quả từ mô hình không đúng yêu cầu.",
                    exception
            );
            default -> new DiagnosisOperationException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "AI_SERVICE_UNAVAILABLE",
                    "Dịch vụ AI hiện không khả dụng. Vui lòng thử lại sau.",
                    exception
            );
        };
    }

    private void rollback(String originalImageUrl, String resultImageUrl) {
        storageService.deleteQuietly(resultImageUrl);
        storageService.deleteQuietly(originalImageUrl);
    }

    private String shortId(String value) {
        if (value == null || value.isBlank()) {
            return "unknown";
        }
        return value.length() <= 8 ? value : value.substring(0, 8);
    }
}
