package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.view.AiPredictionResponse;
import com.polyp.polypweb.view.DiagnosisResultView;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.mock.web.MockMultipartFile;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DiagnosisAnalysisServiceTests {

    @Mock
    private DiagnosisHistoryService historyService;
    @Mock
    private AiInferenceClient aiInferenceClient;
    @Mock
    private FileStorageService storageService;

    private DiagnosisAnalysisService service;
    private MockMultipartFile image;

    @BeforeEach
    void setUp() {
        service = new DiagnosisAnalysisService(
                historyService,
                aiInferenceClient,
                storageService
        );
        image = new MockMultipartFile(
                "image",
                "sample.jpg",
                "image/jpeg",
                new byte[]{(byte) 0xff, (byte) 0xd8, (byte) 0xff, 1}
        );
    }

    @Test
    void invalidModelIsRejectedBeforeFileOrInference() {
        DiagnosisOperationException error = assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(image, "custom-model", "user-id")
        );

        assertEquals("INVALID_MODEL", error.getCode());
        verify(storageService, never()).validateOriginal(any());
        verify(aiInferenceClient, never()).predict(any(), any());
    }

    @Test
    void oversizedUploadIsRejectedAs413() {
        MockMultipartFile oversized = new MockMultipartFile(
                "image",
                "large.jpg",
                "image/jpeg",
                new byte[10 * 1024 * 1024 + 1]
        );

        DiagnosisOperationException error = assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(oversized, "YOLO26s-seg", "user-id")
        );

        assertEquals("FILE_TOO_LARGE", error.getCode());
        assertEquals(413, error.getStatus().value());
    }

    @Test
    void extensionAndMimeMustBothBeWhitelisted() {
        MockMultipartFile text = new MockMultipartFile(
                "image",
                "sample.txt",
                "image/jpeg",
                new byte[]{1}
        );

        DiagnosisOperationException error = assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(text, "YOLO26s-seg", "user-id")
        );

        assertEquals("UNSUPPORTED_MEDIA_TYPE", error.getCode());
    }

    @Test
    void corruptDecodedImageReturns422() {
        doThrow(new StorageException("invalid"))
                .when(storageService).validateOriginal(image);

        DiagnosisOperationException error = assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(image, "YOLO26s-seg", "user-id")
        );

        assertEquals("INVALID_IMAGE", error.getCode());
        assertEquals(422, error.getStatus().value());
    }

    @Test
    void successfulCreateStoresPrincipalUserAndCanonicalModel() {
        AiPredictionResponse prediction = prediction("YOLO26s-seg");
        DiagnosisResultView saved = savedResult();
        when(storageService.storeOriginal(eq(image), any())).thenReturn("/media/original/id.jpg");
        when(aiInferenceClient.predict(image, "YOLO26s-seg")).thenReturn(prediction);
        when(storageService.storeResult(eq("overlay"), any())).thenReturn("/media/results/id_result.jpg");
        when(historyService.saveResult(any(), eq("user-id"))).thenReturn(saved);

        DiagnosisResultView result = service.analyze(image, "YOLO26s-seg", "user-id");

        assertEquals(saved, result);
        ArgumentCaptor<DiagnosisResultView> resultCaptor = ArgumentCaptor.forClass(DiagnosisResultView.class);
        verify(historyService).saveResult(resultCaptor.capture(), eq("user-id"));
        assertEquals("YOLO26s-seg", resultCaptor.getValue().getModelType());
        assertEquals(62.4, resultCaptor.getValue().getConfidence(), 0.0001);
        assertEquals(2, resultCaptor.getValue().getMaskCount());
    }

    @Test
    void inferenceFailureRollsBackOriginalAndNeverSavesDocument() {
        when(storageService.storeOriginal(eq(image), any())).thenReturn("/media/original/id.jpg");
        when(aiInferenceClient.predict(image, "YOLO26s-seg"))
                .thenThrow(new AiServiceException("AI_SERVICE_UNAVAILABLE", "offline"));

        DiagnosisOperationException error = assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(image, "YOLO26s-seg", "user-id")
        );

        assertEquals("AI_SERVICE_UNAVAILABLE", error.getCode());
        verify(storageService).deleteQuietly("/media/original/id.jpg");
        verify(historyService, never()).saveResult(any(), any());
    }

    @Test
    void timeoutMapsTo504AndRollsBackOriginal() {
        when(storageService.storeOriginal(eq(image), any())).thenReturn("/media/original/id.jpg");
        when(aiInferenceClient.predict(image, "YOLO26s-seg"))
                .thenThrow(new AiServiceException("AI_SERVICE_TIMEOUT", "timeout"));

        DiagnosisOperationException error = assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(image, "YOLO26s-seg", "user-id")
        );

        assertEquals(504, error.getStatus().value());
        verify(storageService).deleteQuietly("/media/original/id.jpg");
    }

    @Test
    void modelMismatchIsBlockedAndOriginalIsRolledBack() {
        when(storageService.storeOriginal(eq(image), any())).thenReturn("/media/original/id.jpg");
        when(aiInferenceClient.predict(image, "YOLO26s-seg"))
                .thenReturn(prediction("YOLO26s-TSVM-FP32-seg"));

        DiagnosisOperationException error = assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(image, "YOLO26s-seg", "user-id")
        );

        assertEquals("MODEL_RESPONSE_MISMATCH", error.getCode());
        verify(storageService).deleteQuietly("/media/original/id.jpg");
        verify(storageService, never()).storeResult(any(), any());
    }

    @Test
    void overlayStorageFailureRollsBackOriginal() {
        when(storageService.storeOriginal(eq(image), any())).thenReturn("/media/original/id.jpg");
        when(aiInferenceClient.predict(image, "YOLO26s-seg"))
                .thenReturn(prediction("YOLO26s-seg"));
        when(storageService.storeResult(eq("overlay"), any()))
                .thenThrow(new StorageException("disk full"));

        assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(image, "YOLO26s-seg", "user-id")
        );

        verify(storageService).deleteQuietly("/media/original/id.jpg");
        verify(historyService, never()).saveResult(any(), any());
    }

    @Test
    void mongoSaveFailureRollsBackBothFiles() {
        when(storageService.storeOriginal(eq(image), any())).thenReturn("/media/original/id.jpg");
        when(aiInferenceClient.predict(image, "YOLO26s-seg"))
                .thenReturn(prediction("YOLO26s-seg"));
        when(storageService.storeResult(eq("overlay"), any()))
                .thenReturn("/media/results/id_result.jpg");
        when(historyService.saveResult(any(), eq("user-id")))
                .thenThrow(new RuntimeException("mongo unavailable"));

        assertThrows(
                DiagnosisOperationException.class,
                () -> service.analyze(image, "YOLO26s-seg", "user-id")
        );

        verify(storageService).deleteQuietly("/media/results/id_result.jpg");
        verify(storageService).deleteQuietly("/media/original/id.jpg");
    }

    private AiPredictionResponse prediction(String modelType) {
        AiPredictionResponse prediction = new AiPredictionResponse();
        prediction.setSuccess(true);
        prediction.setDetected(true);
        prediction.setLabel("polyp");
        prediction.setConfidence(0.624);
        prediction.setProcessingTimeMs(148.5);
        prediction.setMaskCount(2);
        prediction.setModelType(modelType);
        prediction.setOriginalFileName("sample.jpg");
        prediction.setResultImageBase64("overlay");
        return prediction;
    }

    private DiagnosisResultView savedResult() {
        return new DiagnosisResultView(
                "diagnosis-1",
                "/diagnoses/diagnosis-1/original-image",
                "/diagnoses/diagnosis-1/result-image",
                "sample.jpg",
                "YOLO26s-seg",
                true,
                "polyp",
                62.4,
                148.5,
                2,
                "",
                java.time.LocalDateTime.now(),
                true,
                null,
                false
        );
    }
}
