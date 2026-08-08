package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.repository.ComparisonHistoryRecord;
import com.polyp.polypweb.repository.ComparisonHistorySearchRepository;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.view.AiPredictionResponse;
import com.polyp.polypweb.view.ComparisonResultView;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.filter.ComparisonHistoryFilter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

@Service
public class ModelComparisonService {

    public static final String BASELINE_MODEL = "YOLO26n-seg";
    public static final String VMAMBA_MODEL = "YOLO26n-VMamba-seg";
    private static final List<String> REQUIRED_MODELS = List.of(BASELINE_MODEL, VMAMBA_MODEL);
    private static final Logger LOGGER = LoggerFactory.getLogger(ModelComparisonService.class);

    private final DiagnosisHistoryRepository repository;
    private final ComparisonHistorySearchRepository historySearchRepository;
    private final DiagnosisHistoryService historyService;
    private final AiInferenceClient aiInferenceClient;
    private final FileStorageService storageService;

    public ModelComparisonService(
            DiagnosisHistoryRepository repository,
            ComparisonHistorySearchRepository historySearchRepository,
            DiagnosisHistoryService historyService,
            AiInferenceClient aiInferenceClient,
            FileStorageService storageService) {
        this.repository = repository;
        this.historySearchRepository = historySearchRepository;
        this.historyService = historyService;
        this.aiInferenceClient = aiInferenceClient;
        this.storageService = storageService;
    }

    public ComparisonResultView compare(MultipartFile image, String userId) {
        UUID comparisonId = UUID.randomUUID();
        String comparisonGroupId = comparisonId.toString();
        String originalImageUrl = null;
        String baselineResultUrl = null;
        String vmambaResultUrl = null;
        List<String> savedDocumentIds = new ArrayList<>();

        try {
            String validatedFileName = ImageUploadValidator.validate(image, storageService);
            requireModelsAvailable();
            originalImageUrl = storageService.storeOriginal(image, comparisonId);

            AiPredictionResponse baselinePrediction = predict(
                    image,
                    BASELINE_MODEL
            );
            baselineResultUrl = storageService.storeComparisonResult(
                    baselinePrediction.getResultImageBase64(),
                    comparisonId,
                    "baseline"
            );

            AiPredictionResponse vmambaPrediction = predict(
                    image,
                    VMAMBA_MODEL
            );
            vmambaResultUrl = storageService.storeComparisonResult(
                    vmambaPrediction.getResultImageBase64(),
                    comparisonId,
                    "vmamba"
            );

            LocalDateTime createdAt = LocalDateTime.now();
            String fileName = resolveFileName(validatedFileName, baselinePrediction);
            DiagnosisHistory baselineHistory = createHistory(
                    baselinePrediction,
                    userId,
                    fileName,
                    originalImageUrl,
                    baselineResultUrl,
                    createdAt,
                    comparisonGroupId
            );
            DiagnosisHistory vmambaHistory = createHistory(
                    vmambaPrediction,
                    userId,
                    fileName,
                    originalImageUrl,
                    vmambaResultUrl,
                    createdAt,
                    comparisonGroupId
            );

            DiagnosisHistory savedBaseline = repository.save(baselineHistory);
            savedDocumentIds.add(savedBaseline.getId());
            DiagnosisHistory savedVmamba = repository.save(vmambaHistory);
            savedDocumentIds.add(savedVmamba.getId());

            return toCompleteComparison(List.of(savedBaseline, savedVmamba))
                    .orElseThrow(() -> new ModelComparisonException(
                            "Dữ liệu phiên so sánh vừa lưu không nhất quán."
                    ));
        } catch (RuntimeException exception) {
            rollback(savedDocumentIds, originalImageUrl, baselineResultUrl, vmambaResultUrl);
            if (exception instanceof ModelComparisonException comparisonException) {
                throw comparisonException;
            }
            if (exception instanceof com.polyp.polypweb.exception.UploadValidationException validationException) {
                throw new ModelComparisonException(
                        validationException.getStatus(),
                        validationException.getCode(),
                        validationException.getMessage(),
                        validationException
                );
            }
            if (exception instanceof AiServiceException aiServiceException) {
                throw availabilityFailure(aiServiceException);
            }
            if (exception instanceof StorageException storageException) {
                throw new ModelComparisonException(
                        HttpStatus.INTERNAL_SERVER_ERROR,
                        "STORAGE_FAILURE",
                        "Không thể lưu ảnh phiên so sánh. Dữ liệu tạm đã được dọn dẹp.",
                        storageException
                );
            }
            LOGGER.error("Không thể hoàn tất phiên so sánh {}", comparisonGroupId, exception);
            throw new ModelComparisonException(
                    HttpStatus.INTERNAL_SERVER_ERROR,
                    "COMPARISON_SAVE_FAILED",
                    "Không thể lưu phiên so sánh. Dữ liệu tạm đã được rollback.",
                    exception
            );
        }
    }

    public Optional<ComparisonResultView> findForUser(
            String comparisonGroupId,
            String userId,
            boolean admin) {
        return normalizeGroupId(comparisonGroupId)
                .flatMap(groupId -> {
                    List<DiagnosisHistory> histories = admin
                            ? repository.findAllByComparisonGroupIdOrderByCreatedAtAsc(groupId)
                            : repository.findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(
                                    groupId,
                                    userId
                            );
                    if (histories.isEmpty()
                            && !admin
                            && !repository.findAllByComparisonGroupIdOrderByCreatedAtAsc(groupId).isEmpty()) {
                        throw new AccessDeniedException("Bạn không có quyền truy cập phiên so sánh này.");
                    }
                    return toCompleteComparison(histories);
                });
    }

    public ComparisonResultView requireForUser(
            String comparisonGroupId,
            String userId,
            boolean admin) {
        String groupId = normalizeGroupId(comparisonGroupId)
                .orElseThrow(this::notFound);
        List<DiagnosisHistory> histories = admin
                ? repository.findAllByComparisonGroupIdOrderByCreatedAtAsc(groupId)
                : repository.findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(groupId, userId);
        if (histories.isEmpty()) {
            if (!admin && !repository.findAllByComparisonGroupIdOrderByCreatedAtAsc(groupId).isEmpty()) {
                throw new AccessDeniedException("Bạn không có quyền truy cập phiên so sánh này.");
            }
            throw notFound();
        }
        return toCompleteComparison(histories)
                .orElseThrow(() -> new ModelComparisonException(
                        HttpStatus.CONFLICT,
                        "INCOMPLETE_COMPARISON",
                        "Phiên so sánh không đầy đủ hoặc dữ liệu hai mô hình không nhất quán."
                ));
    }

    public Page<ComparisonResultView> findHistoryPage(
            String userId,
            ComparisonHistoryFilter filter) {
        return historySearchRepository.search(userId, filter)
                .map(this::toComparisonView);
    }

    public boolean deleteForUser(
            String comparisonGroupId,
            String userId,
            boolean admin) {
        Optional<String> normalizedGroupId = normalizeGroupId(comparisonGroupId);
        if (normalizedGroupId.isEmpty()) {
            return false;
        }

        List<DiagnosisHistory> histories = admin
                ? repository.findAllByComparisonGroupIdOrderByCreatedAtAsc(normalizedGroupId.get())
                : repository.findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(
                        normalizedGroupId.get(),
                        userId
                );
        if (histories.isEmpty()) {
            if (!admin
                    && !repository.findAllByComparisonGroupIdOrderByCreatedAtAsc(
                            normalizedGroupId.get()
                    ).isEmpty()) {
                throw new AccessDeniedException("Bạn không có quyền xóa phiên so sánh này.");
            }
            return false;
        }

        Set<String> mediaUrls = new LinkedHashSet<>();
        histories.forEach(history -> {
            mediaUrls.add(history.getOriginalImageUrl());
            mediaUrls.add(history.getResultImageUrl());
        });

        try {
            repository.deleteAll(histories);
            mediaUrls.stream()
                    .filter(Objects::nonNull)
                    .forEach(storageService::deleteQuietly);
            return true;
        } catch (RuntimeException exception) {
            LOGGER.error("Không thể xóa phiên so sánh {}", normalizedGroupId.get(), exception);
            throw new ModelComparisonException(
                    "Không thể xóa phiên so sánh khỏi MongoDB.",
                    exception
            );
        }
    }

    private void requireModelsAvailable() {
        try {
            aiInferenceClient.requireModelsAvailable(REQUIRED_MODELS);
        } catch (AiServiceException exception) {
            throw availabilityFailure(exception);
        }
    }

    private AiPredictionResponse predict(MultipartFile image, String modelType) {
        try {
            return aiInferenceClient.predict(image, modelType);
        } catch (AiServiceException exception) {
            String phase = BASELINE_MODEL.equals(modelType) ? "BASELINE" : "VMAMBA";
            String code = switch (exception.getCode()) {
                case "MODEL_UNAVAILABLE" -> phase + "_MODEL_UNAVAILABLE";
                case "AI_SERVICE_TIMEOUT" -> phase + "_TIMEOUT";
                case "MODEL_RESPONSE_MISMATCH" -> "MODEL_RESPONSE_MISMATCH";
                default -> "AI_SERVICE_UNAVAILABLE";
            };
            HttpStatus status = code.endsWith("_TIMEOUT")
                    ? HttpStatus.GATEWAY_TIMEOUT
                    : "MODEL_RESPONSE_MISMATCH".equals(code)
                    ? HttpStatus.BAD_GATEWAY
                    : HttpStatus.SERVICE_UNAVAILABLE;
            throw new ModelComparisonException(status, code, safeAiMessage(code), exception);
        }
    }

    private ModelComparisonException availabilityFailure(AiServiceException exception) {
        String code = exception.getCode();
        if ("MODEL_UNAVAILABLE".equals(code)) {
            String message = exception.getMessage() == null ? "" : exception.getMessage();
            code = message.contains(VMAMBA_MODEL)
                    ? "VMAMBA_MODEL_UNAVAILABLE"
                    : "BASELINE_MODEL_UNAVAILABLE";
        }
        HttpStatus status = "AI_SERVICE_TIMEOUT".equals(code)
                ? HttpStatus.GATEWAY_TIMEOUT
                : HttpStatus.SERVICE_UNAVAILABLE;
        return new ModelComparisonException(status, code, safeAiMessage(code), exception);
    }

    private String safeAiMessage(String code) {
        return switch (code) {
            case "BASELINE_MODEL_UNAVAILABLE" -> "Mô hình Baseline hiện không khả dụng.";
            case "VMAMBA_MODEL_UNAVAILABLE" -> "Mô hình VMamba hiện không khả dụng.";
            case "BASELINE_TIMEOUT" -> "Lượt inference Baseline phản hồi quá thời gian.";
            case "VMAMBA_TIMEOUT" -> "Lượt inference VMamba phản hồi quá thời gian.";
            case "MODEL_RESPONSE_MISMATCH" -> "Dịch vụ AI trả về kết quả từ mô hình không đúng yêu cầu.";
            default -> "Dịch vụ AI hiện không khả dụng. Vui lòng thử lại sau.";
        };
    }

    private DiagnosisHistory createHistory(
            AiPredictionResponse prediction,
            String userId,
            String fileName,
            String originalImageUrl,
            String resultImageUrl,
            LocalDateTime createdAt,
            String comparisonGroupId) {
        return new DiagnosisHistory(
                userId,
                fileName,
                prediction.getModelType(),
                prediction.isDetected(),
                prediction.getLabel(),
                confidencePercent(prediction.getConfidence()),
                prediction.getProcessingTimeMs(),
                prediction.getMaskCount(),
                originalImageUrl,
                resultImageUrl,
                createdAt,
                comparisonGroupId,
                true
        );
    }

    private Optional<ComparisonResultView> toCompleteComparison(List<DiagnosisHistory> histories) {
        if (histories.size() != 2) {
            return Optional.empty();
        }

        DiagnosisHistory baseline = histories.stream()
                .filter(history -> BASELINE_MODEL.equals(history.getModelType()))
                .findFirst()
                .orElse(null);
        DiagnosisHistory vmamba = histories.stream()
                .filter(history -> VMAMBA_MODEL.equals(history.getModelType()))
                .findFirst()
                .orElse(null);
        if (baseline == null
                || vmamba == null
                || !baseline.isComparisonResult()
                || !vmamba.isComparisonResult()
                || !Objects.equals(baseline.getComparisonGroupId(), vmamba.getComparisonGroupId())
                || !Objects.equals(baseline.getUserId(), vmamba.getUserId())
                || !Objects.equals(baseline.getFileName(), vmamba.getFileName())
                || !Objects.equals(baseline.getOriginalImageUrl(), vmamba.getOriginalImageUrl())) {
            return Optional.empty();
        }

        DiagnosisResultView baselineView = historyService.toView(baseline);
        DiagnosisResultView vmambaView = historyService.toView(vmamba);
        LocalDateTime createdAt = baseline.getCreatedAt() != null
                ? baseline.getCreatedAt()
                : vmamba.getCreatedAt();
        return Optional.of(new ComparisonResultView(
                baseline.getComparisonGroupId(),
                baselineView,
                vmambaView,
                baselineView.getOriginalImageUrl(),
                baseline.getFileName(),
                createdAt
        ));
    }

    private ComparisonResultView toComparisonView(ComparisonHistoryRecord record) {
        return new ComparisonResultView(
                record.comparisonGroupId(),
                historyService.toView(record.baseline()),
                historyService.toView(record.vmamba()),
                "/diagnoses/" + record.baseline().getId() + "/original-image",
                record.fileName(),
                record.createdAt()
        );
    }

    private void rollback(
            List<String> savedDocumentIds,
            String originalImageUrl,
            String baselineResultUrl,
            String vmambaResultUrl) {
        for (String documentId : savedDocumentIds) {
            if (documentId == null) {
                continue;
            }
            try {
                repository.deleteById(documentId);
            } catch (RuntimeException rollbackException) {
                LOGGER.error("Không thể rollback document so sánh {}", documentId, rollbackException);
            }
        }
        storageService.deleteQuietly(vmambaResultUrl);
        storageService.deleteQuietly(baselineResultUrl);
        storageService.deleteQuietly(originalImageUrl);
    }

    private Optional<String> normalizeGroupId(String comparisonGroupId) {
        if (comparisonGroupId == null || comparisonGroupId.isBlank()) {
            return Optional.empty();
        }
        try {
            return Optional.of(UUID.fromString(comparisonGroupId).toString());
        } catch (IllegalArgumentException exception) {
            return Optional.empty();
        }
    }

    private String resolveFileName(
            String validatedFileName,
            AiPredictionResponse prediction) {
        String fileName = prediction.getOriginalFileName();
        if (fileName == null || fileName.isBlank()) {
            fileName = validatedFileName;
        }
        if (fileName == null || fileName.isBlank()) {
            return "anh-noi-soi.jpg";
        }
        String normalized = fileName.replace('\\', '/');
        return normalized.substring(normalized.lastIndexOf('/') + 1);
    }

    private double confidencePercent(double confidence) {
        double percent = confidence <= 1 ? confidence * 100 : confidence;
        return Math.max(0, Math.min(100, percent));
    }

    private ModelComparisonException notFound() {
        return new ModelComparisonException(
                HttpStatus.NOT_FOUND,
                "RESOURCE_NOT_FOUND",
                "Không tìm thấy phiên so sánh."
        );
    }
}
