package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.repository.ComparisonHistorySearchRepository;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.view.AiPredictionResponse;
import com.polyp.polypweb.view.ComparisonResultView;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.filter.ComparisonHistoryFilter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ModelComparisonServiceTests {

    private static final String USER_ID = "user-a";

    @Mock
    private DiagnosisHistoryRepository repository;
    @Mock
    private ComparisonHistorySearchRepository historySearchRepository;
    @Mock
    private DiagnosisHistoryService historyService;
    @Mock
    private AiInferenceClient aiInferenceClient;
    @Mock
    private FileStorageService storageService;
    @Mock
    private MultipartFile image;

    private ModelComparisonService service;

    @BeforeEach
    void setUp() {
        service = new ModelComparisonService(
                repository,
                historySearchRepository,
                historyService,
                aiInferenceClient,
                storageService
        );
    }

    @Test
    void compareSavesTwoLinkedDocumentsAndRunsModelsSequentially() {
        prepareComparisonDefaults();
        when(historyService.toView(any(DiagnosisHistory.class)))
                .thenAnswer(invocation -> toView(invocation.getArgument(0)));
        AiPredictionResponse baseline = prediction(
                ModelComparisonService.BASELINE_MODEL,
                true,
                0.71,
                2,
                100
        );
        AiPredictionResponse vmamba = prediction(
                ModelComparisonService.VMAMBA_MODEL,
                false,
                0,
                0,
                220
        );
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenReturn(baseline);
        when(aiInferenceClient.predict(image, ModelComparisonService.VMAMBA_MODEL))
                .thenReturn(vmamba);
        when(storageService.storeComparisonResult(eq("baseline-base64"), any(UUID.class), eq("baseline")))
                .thenReturn("/media/results/baseline.jpg");
        when(storageService.storeComparisonResult(eq("vmamba-base64"), any(UUID.class), eq("vmamba")))
                .thenReturn("/media/results/vmamba.jpg");

        AtomicInteger sequence = new AtomicInteger();
        when(repository.save(any(DiagnosisHistory.class))).thenAnswer(invocation -> {
            DiagnosisHistory history = invocation.getArgument(0);
            history.setId("doc-" + sequence.incrementAndGet());
            return history;
        });

        ComparisonResultView result = service.compare(image, USER_ID);

        assertNotNull(UUID.fromString(result.getComparisonGroupId()));
        assertEquals(ModelComparisonService.BASELINE_MODEL, result.getBaselineResult().getModelType());
        assertEquals(ModelComparisonService.VMAMBA_MODEL, result.getVmambaResult().getModelType());
        assertEquals(2, result.getBaselineResult().getMaskCount());
        assertEquals(result.getBaselineResult().getComparisonGroupId(),
                result.getVmambaResult().getComparisonGroupId());
        ArgumentCaptor<DiagnosisHistory> historyCaptor =
                ArgumentCaptor.forClass(DiagnosisHistory.class);
        verify(repository, times(2)).save(historyCaptor.capture());
        assertEquals(List.of(USER_ID, USER_ID), historyCaptor.getAllValues()
                .stream()
                .map(DiagnosisHistory::getUserId)
                .toList());

        InOrder order = inOrder(storageService, aiInferenceClient, repository);
        order.verify(storageService).validateOriginal(image);
        order.verify(aiInferenceClient).requireModelsAvailable(anyList());
        order.verify(storageService).storeOriginal(eq(image), any(UUID.class));
        order.verify(aiInferenceClient).predict(image, ModelComparisonService.BASELINE_MODEL);
        order.verify(storageService)
                .storeComparisonResult(eq("baseline-base64"), any(UUID.class), eq("baseline"));
        order.verify(aiInferenceClient).predict(image, ModelComparisonService.VMAMBA_MODEL);
        order.verify(storageService)
                .storeComparisonResult(eq("vmamba-base64"), any(UUID.class), eq("vmamba"));
        order.verify(repository, times(2)).save(any(DiagnosisHistory.class));
    }

    @Test
    void vmambaFailureRollsBackOriginalAndBaselineOverlay() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenReturn(prediction(
                        ModelComparisonService.BASELINE_MODEL,
                        true,
                        0.65,
                        1,
                        110
                ));
        when(storageService.storeComparisonResult(eq("baseline-base64"), any(UUID.class), eq("baseline")))
                .thenReturn("/media/results/baseline.jpg");
        when(aiInferenceClient.predict(image, ModelComparisonService.VMAMBA_MODEL))
                .thenThrow(new AiServiceException("VMamba unavailable"));

        assertThrows(ModelComparisonException.class, () -> service.compare(image, USER_ID));

        verify(repository, never()).save(any(DiagnosisHistory.class));
        verify(storageService).deleteQuietly("/media/results/baseline.jpg");
        verify(storageService).deleteQuietly("/media/original/shared.jpg");
        verify(storageService, never())
                .storeComparisonResult(any(), any(UUID.class), eq("vmamba"));
    }

    @Test
    void baselineFailureRollsBackOriginalWithoutRunningVmamba() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenThrow(new AiServiceException("Baseline unavailable"));

        assertThrows(ModelComparisonException.class, () -> service.compare(image, USER_ID));

        verify(storageService).deleteQuietly("/media/original/shared.jpg");
        verify(storageService, never())
                .storeComparisonResult(any(), any(UUID.class), any());
        verify(aiInferenceClient, never())
                .predict(image, ModelComparisonService.VMAMBA_MODEL);
        verify(repository, never()).save(any(DiagnosisHistory.class));
    }

    @Test
    void secondDocumentFailureDeletesFirstDocumentAndAllFiles() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenReturn(prediction(
                        ModelComparisonService.BASELINE_MODEL,
                        true,
                        0.65,
                        1,
                        110
                ));
        when(aiInferenceClient.predict(image, ModelComparisonService.VMAMBA_MODEL))
                .thenReturn(prediction(
                        ModelComparisonService.VMAMBA_MODEL,
                        true,
                        0.61,
                        1,
                        210
                ));
        when(storageService.storeComparisonResult(eq("baseline-base64"), any(UUID.class), eq("baseline")))
                .thenReturn("/media/results/baseline.jpg");
        when(storageService.storeComparisonResult(eq("vmamba-base64"), any(UUID.class), eq("vmamba")))
                .thenReturn("/media/results/vmamba.jpg");

        AtomicInteger saveCount = new AtomicInteger();
        when(repository.save(any(DiagnosisHistory.class))).thenAnswer(invocation -> {
            if (saveCount.incrementAndGet() == 2) {
                throw new RuntimeException("simulated second save failure");
            }
            DiagnosisHistory history = invocation.getArgument(0);
            history.setId("baseline-doc");
            return history;
        });

        assertThrows(ModelComparisonException.class, () -> service.compare(image, USER_ID));

        verify(repository).deleteById("baseline-doc");
        verify(storageService).deleteQuietly("/media/results/vmamba.jpg");
        verify(storageService).deleteQuietly("/media/results/baseline.jpg");
        verify(storageService).deleteQuietly("/media/original/shared.jpg");
    }

    @Test
    void incompleteComparisonGroupIsSkipped() {
        ComparisonHistoryFilter filter = new ComparisonHistoryFilter().normalize();
        when(historySearchRepository.search(USER_ID, filter)).thenReturn(Page.empty());

        assertTrue(service.findHistoryPage(USER_ID, filter).isEmpty());
    }

    @Test
    void userCannotViewAnotherUsersComparison() {
        String groupId = UUID.randomUUID().toString();
        when(repository.findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(groupId, USER_ID))
                .thenReturn(List.of());
        when(repository.findAllByComparisonGroupIdOrderByCreatedAtAsc(groupId))
                .thenReturn(List.of(history(ModelComparisonService.BASELINE_MODEL, groupId)));

        assertThrows(
                org.springframework.security.access.AccessDeniedException.class,
                () -> service.findForUser(groupId, USER_ID, false)
        );
    }

    @Test
    void userCannotDeleteAnotherUsersComparison() {
        String groupId = UUID.randomUUID().toString();
        when(repository.findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(groupId, USER_ID))
                .thenReturn(List.of());
        when(repository.findAllByComparisonGroupIdOrderByCreatedAtAsc(groupId))
                .thenReturn(List.of(history(ModelComparisonService.BASELINE_MODEL, groupId)));

        assertThrows(
                org.springframework.security.access.AccessDeniedException.class,
                () -> service.deleteForUser(groupId, USER_ID, false)
        );
        verify(repository, never()).deleteAll(anyList());
        verify(storageService, never()).deleteQuietly(any());
    }

    @Test
    void ownerDeletesComparisonOriginalOnlyOnce() {
        String groupId = UUID.randomUUID().toString();
        DiagnosisHistory baseline = history(ModelComparisonService.BASELINE_MODEL, groupId);
        DiagnosisHistory vmamba = history(ModelComparisonService.VMAMBA_MODEL, groupId);
        vmamba.setResultImageUrl("/media/results/vmamba.jpg");
        when(repository.findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(groupId, USER_ID))
                .thenReturn(List.of(baseline, vmamba));

        assertTrue(service.deleteForUser(groupId, USER_ID, false));

        verify(repository).deleteAll(List.of(baseline, vmamba));
        verify(storageService, times(1)).deleteQuietly("/media/original/shared.jpg");
        verify(storageService).deleteQuietly("/media/results/result.jpg");
        verify(storageService).deleteQuietly("/media/results/vmamba.jpg");
    }

    @Test
    void baselineModelUnavailableHasStableCodeAndRollsBackOriginal() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenThrow(new AiServiceException("MODEL_UNAVAILABLE", "offline"));

        ModelComparisonException exception = assertThrows(
                ModelComparisonException.class,
                () -> service.compare(image, USER_ID)
        );

        assertEquals("BASELINE_MODEL_UNAVAILABLE", exception.getCode());
        assertEquals(503, exception.getStatus().value());
        verify(storageService).deleteQuietly("/media/original/shared.jpg");
        verify(repository, never()).save(any());
    }

    @Test
    void vmambaTimeoutHasStableCodeAndRollsBackBaselineOverlay() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenReturn(prediction(ModelComparisonService.BASELINE_MODEL, true, 0.6, 1, 100));
        when(storageService.storeComparisonResult(eq("baseline-base64"), any(UUID.class), eq("baseline")))
                .thenReturn("/media/results/baseline.jpg");
        when(aiInferenceClient.predict(image, ModelComparisonService.VMAMBA_MODEL))
                .thenThrow(new AiServiceException("AI_SERVICE_TIMEOUT", "timeout"));

        ModelComparisonException exception = assertThrows(
                ModelComparisonException.class,
                () -> service.compare(image, USER_ID)
        );

        assertEquals("VMAMBA_TIMEOUT", exception.getCode());
        assertEquals(504, exception.getStatus().value());
        verify(storageService).deleteQuietly("/media/results/baseline.jpg");
        verify(storageService).deleteQuietly("/media/original/shared.jpg");
    }

    @Test
    void modelResponseMismatchIsBlockedAndRolledBack() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenThrow(new AiServiceException("MODEL_RESPONSE_MISMATCH", "wrong"));

        ModelComparisonException exception = assertThrows(
                ModelComparisonException.class,
                () -> service.compare(image, USER_ID)
        );

        assertEquals("MODEL_RESPONSE_MISMATCH", exception.getCode());
        assertEquals(502, exception.getStatus().value());
        verify(storageService).deleteQuietly("/media/original/shared.jpg");
    }

    @Test
    void baselineOverlayStorageFailureRollsBackOriginal() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenReturn(prediction(ModelComparisonService.BASELINE_MODEL, true, 0.6, 1, 100));
        when(storageService.storeComparisonResult(eq("baseline-base64"), any(UUID.class), eq("baseline")))
                .thenThrow(new StorageException("disk full"));

        ModelComparisonException exception = assertThrows(
                ModelComparisonException.class,
                () -> service.compare(image, USER_ID)
        );

        assertEquals("STORAGE_FAILURE", exception.getCode());
        verify(storageService).deleteQuietly("/media/original/shared.jpg");
        verify(repository, never()).save(any());
    }

    @Test
    void vmambaOverlayStorageFailureRollsBackOriginalAndBaseline() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenReturn(prediction(ModelComparisonService.BASELINE_MODEL, true, 0.6, 1, 100));
        when(aiInferenceClient.predict(image, ModelComparisonService.VMAMBA_MODEL))
                .thenReturn(prediction(ModelComparisonService.VMAMBA_MODEL, true, 0.7, 1, 120));
        when(storageService.storeComparisonResult(eq("baseline-base64"), any(UUID.class), eq("baseline")))
                .thenReturn("/media/results/baseline.jpg");
        when(storageService.storeComparisonResult(eq("vmamba-base64"), any(UUID.class), eq("vmamba")))
                .thenThrow(new StorageException("disk full"));

        assertThrows(ModelComparisonException.class, () -> service.compare(image, USER_ID));

        verify(storageService).deleteQuietly("/media/results/baseline.jpg");
        verify(storageService).deleteQuietly("/media/original/shared.jpg");
        verify(repository, never()).save(any());
    }

    @Test
    void firstDocumentSaveFailureRollsBackEveryFile() {
        prepareSuccessfulInferenceAndStorage();
        when(repository.save(any(DiagnosisHistory.class)))
                .thenThrow(new RuntimeException("mongo offline"));

        ModelComparisonException exception = assertThrows(
                ModelComparisonException.class,
                () -> service.compare(image, USER_ID)
        );

        assertEquals("COMPARISON_SAVE_FAILED", exception.getCode());
        verify(storageService).deleteQuietly("/media/results/vmamba.jpg");
        verify(storageService).deleteQuietly("/media/results/baseline.jpg");
        verify(storageService).deleteQuietly("/media/original/shared.jpg");
    }

    @Test
    void requireGroupRejectsMissingVmamba() {
        String groupId = UUID.randomUUID().toString();
        when(repository.findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(groupId, USER_ID))
                .thenReturn(List.of(history(ModelComparisonService.BASELINE_MODEL, groupId)));

        ModelComparisonException exception = assertThrows(
                ModelComparisonException.class,
                () -> service.requireForUser(groupId, USER_ID, false)
        );

        assertEquals("INCOMPLETE_COMPARISON", exception.getCode());
        assertEquals(409, exception.getStatus().value());
    }

    @Test
    void requireGroupRejectsDifferentOriginalImages() {
        String groupId = UUID.randomUUID().toString();
        DiagnosisHistory baseline = history(ModelComparisonService.BASELINE_MODEL, groupId);
        DiagnosisHistory vmamba = history(ModelComparisonService.VMAMBA_MODEL, groupId);
        vmamba.setOriginalImageUrl("/media/original/other.jpg");
        when(repository.findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(groupId, USER_ID))
                .thenReturn(List.of(baseline, vmamba));

        ModelComparisonException exception = assertThrows(
                ModelComparisonException.class,
                () -> service.requireForUser(groupId, USER_ID, false)
        );

        assertEquals("INCOMPLETE_COMPARISON", exception.getCode());
    }

    @Test
    void unavailableHealthIdentifiesVmambaModel() {
        when(image.isEmpty()).thenReturn(false);
        when(image.getSize()).thenReturn(1024L);
        when(image.getContentType()).thenReturn("image/jpeg");
        when(image.getOriginalFilename()).thenReturn("same-image.jpg");
        org.mockito.Mockito.doThrow(new AiServiceException(
                        "MODEL_UNAVAILABLE",
                        ModelComparisonService.VMAMBA_MODEL + " unavailable"))
                .when(aiInferenceClient).requireModelsAvailable(anyList());

        ModelComparisonException exception = assertThrows(
                ModelComparisonException.class,
                () -> service.compare(image, USER_ID)
        );

        assertEquals("VMAMBA_MODEL_UNAVAILABLE", exception.getCode());
        verify(storageService, never()).storeOriginal(any(), any());
    }

    private AiPredictionResponse prediction(
            String model,
            boolean detected,
            double confidence,
            int maskCount,
            double processingTime) {
        AiPredictionResponse response = new AiPredictionResponse();
        response.setSuccess(true);
        response.setModelType(model);
        response.setOriginalFileName("same-image.jpg");
        response.setDetected(detected);
        response.setLabel(detected ? "polyp" : null);
        response.setConfidence(confidence);
        response.setMaskCount(maskCount);
        response.setProcessingTimeMs(processingTime);
        response.setResultImageBase64(
                model.equals(ModelComparisonService.BASELINE_MODEL)
                        ? "baseline-base64"
                        : "vmamba-base64"
        );
        return response;
    }

    private void prepareComparisonDefaults() {
        when(image.isEmpty()).thenReturn(false);
        when(image.getSize()).thenReturn(1024L);
        when(image.getContentType()).thenReturn("image/jpeg");
        when(image.getOriginalFilename()).thenReturn("same-image.jpg");
        when(storageService.storeOriginal(eq(image), any(UUID.class)))
                .thenReturn("/media/original/shared.jpg");
    }

    private void prepareSuccessfulInferenceAndStorage() {
        prepareComparisonDefaults();
        when(aiInferenceClient.predict(image, ModelComparisonService.BASELINE_MODEL))
                .thenReturn(prediction(ModelComparisonService.BASELINE_MODEL, true, 0.6, 1, 100));
        when(aiInferenceClient.predict(image, ModelComparisonService.VMAMBA_MODEL))
                .thenReturn(prediction(ModelComparisonService.VMAMBA_MODEL, true, 0.7, 1, 120));
        when(storageService.storeComparisonResult(eq("baseline-base64"), any(UUID.class), eq("baseline")))
                .thenReturn("/media/results/baseline.jpg");
        when(storageService.storeComparisonResult(eq("vmamba-base64"), any(UUID.class), eq("vmamba")))
                .thenReturn("/media/results/vmamba.jpg");
    }

    private DiagnosisHistory history(String model, String groupId) {
        return new DiagnosisHistory(
                USER_ID,
                "same-image.jpg",
                model,
                true,
                "polyp",
                70,
                100,
                1,
                "/media/original/shared.jpg",
                "/media/results/result.jpg",
                java.time.LocalDateTime.now(),
                groupId,
                true
        );
    }

    private DiagnosisResultView toView(DiagnosisHistory history) {
        return new DiagnosisResultView(
                history.getId(),
                history.getOriginalImageUrl(),
                history.getResultImageUrl(),
                history.getFileName(),
                history.getModelType(),
                history.isDetected(),
                history.getLabel(),
                history.getConfidence(),
                history.getProcessingTimeMs(),
                history.getMaskCount(),
                "1280 × 720 px",
                history.getCreatedAt(),
                true,
                history.getComparisonGroupId(),
                true
        );
    }
}
