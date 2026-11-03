package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.repository.ComparisonHistorySearchRepository;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.HistorySearchRepository;
import com.polyp.polypweb.view.AiPredictionResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockMultipartFile;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.nio.file.Path;
import java.util.Base64;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class ImageMetadataRegressionTests {

    @TempDir
    Path temporaryDirectory;

    private DiagnosisHistoryRepository repository;
    private FileStorageService storage;
    private DiagnosisHistoryService historyService;
    private AiInferenceClient ai;

    @BeforeEach
    void setUp() {
        repository = mock(DiagnosisHistoryRepository.class);
        storage = new FileStorageService(temporaryDirectory.toString());
        historyService = new DiagnosisHistoryService(repository, mock(HistorySearchRepository.class), storage);
        ai = mock(AiInferenceClient.class);
        AtomicInteger sequence = new AtomicInteger();
        lenient().when(repository.save(any(DiagnosisHistory.class))).thenAnswer(invocation -> {
            DiagnosisHistory history = invocation.getArgument(0);
            history.setId("record-" + sequence.incrementAndGet());
            return history;
        });
    }

    @Test
    void uploadPersistsActual621By530AndReturnsItToTheResultPage() throws Exception {
        var upload = image(621, 530);
        when(ai.predict(upload, DiagnosisModel.VMAMBA.getModelType()))
                .thenReturn(prediction(DiagnosisModel.VMAMBA.getModelType()));
        var analysis = new DiagnosisAnalysisService(historyService, ai, storage);

        var result = analysis.analyze(upload, DiagnosisModel.VMAMBA.getModelType(), "user-a");

        assertEquals("621 × 530 px", result.getImageSize());
        var captured = ArgumentCaptor.forClass(DiagnosisHistory.class);
        verify(repository).save(captured.capture());
        assertEquals(621, captured.getValue().getImageWidth());
        assertEquals(530, captured.getValue().getImageHeight());
    }

    @Test
    void comparisonPersistsDimensionsForBothModels() throws Exception {
        var upload = image(621, 530);
        when(ai.predict(upload, DiagnosisModel.BASELINE.getModelType()))
                .thenReturn(prediction(DiagnosisModel.BASELINE.getModelType()));
        when(ai.predict(upload, DiagnosisModel.VMAMBA.getModelType()))
                .thenReturn(prediction(DiagnosisModel.VMAMBA.getModelType()));
        var comparison = new ModelComparisonService(
                repository, mock(ComparisonHistorySearchRepository.class), historyService, ai, storage);

        var result = comparison.compare(upload, "user-a");

        assertEquals("621 × 530 px", result.getBaselineResult().getImageSize());
        assertEquals("621 × 530 px", result.getVmambaResult().getImageSize());
        var captured = ArgumentCaptor.forClass(DiagnosisHistory.class);
        verify(repository, times(2)).save(captured.capture());
        for (var history : captured.getAllValues()) {
            assertEquals(621, history.getImageWidth());
            assertEquals(530, history.getImageHeight());
        }
    }

    @Test
    void legacyRecordReadsRealOriginalWithoutWritingAnImplicitMigration() throws Exception {
        var history = new DiagnosisHistory();
        history.setOriginalImageUrl(storage.storeOriginal(image(319, 247), UUID.randomUUID()));

        assertEquals("319 × 247 px", historyService.toView(history).getImageSize());
        assertNull(history.getImageWidth());
        assertNull(history.getImageHeight());
        verify(repository, never()).save(any());
    }

    @Test
    void legacyRecordWithMissingOriginalShowsUnknownInsteadOfInventedDimensions() {
        var history = new DiagnosisHistory();
        history.setOriginalImageUrl("/media/original/" + UUID.randomUUID() + ".jpg");

        assertEquals("Chưa xác định", historyService.toView(history).getImageSize());
        verify(repository, never()).save(any());
    }

    @Test
    void persistedMetadataRemainsAvailableIfOriginalIsMissing() {
        var history = new DiagnosisHistory();
        history.setImageWidth(621);
        history.setImageHeight(530);

        assertEquals("621 × 530 px", historyService.toView(history).getImageSize());
    }

    private MockMultipartFile image(int width, int height) throws Exception {
        var bytes = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB), "png", bytes);
        return new MockMultipartFile("image", "sample.png", "image/png", bytes.toByteArray());
    }

    private AiPredictionResponse prediction(String modelType) throws Exception {
        var bytes = new ByteArrayOutputStream();
        ImageIO.write(new BufferedImage(10, 10, BufferedImage.TYPE_INT_RGB), "jpg", bytes);
        var response = new AiPredictionResponse();
        response.setModelType(modelType);
        response.setSuccess(true);
        response.setDetected(true);
        response.setLabel("polyp");
        response.setConfidence(0.6);
        response.setMaskCount(2);
        response.setProcessingTimeMs(100);
        response.setOriginalFileName("sample.png");
        response.setResultImageBase64(Base64.getEncoder().encodeToString(bytes.toByteArray()));
        return response;
    }
}
