package com.polyp.polypweb.service;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.document.VideoAnalysis;
import com.polyp.polypweb.exception.DiagnosisOperationException;
import com.polyp.polypweb.repository.VideoAnalysisRepository;
import com.polyp.polypweb.view.AiVideoPredictionResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.mock.web.MockMultipartFile;

import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class VideoAnalysisServiceTests {

    @Mock
    private VideoAnalysisRepository repository;
    @Mock
    private AiInferenceClient aiInferenceClient;
    @Mock
    private VideoStorageService storageService;

    private VideoAnalysisService service;

    @BeforeEach
    void setUp() {
        service = new VideoAnalysisService(repository, aiInferenceClient, storageService);
    }

    private static MockMultipartFile mp4(String name) {
        byte[] content = new byte[64];
        content[4] = 'f';
        content[5] = 't';
        content[6] = 'y';
        content[7] = 'p';
        return new MockMultipartFile("video", name, "video/mp4", content);
    }

    private static AiVideoPredictionResponse prediction(String modelType) {
        return new AiVideoPredictionResponse(
                true, modelType, "clip.mp4", 25, 250, 10, 640, 480, 5, 5, false, 25.0, 250, 200, 50, 12, 0.91, 4000, 60, 12.5,
                List.of(new VideoAnalysis.TimelinePoint(0, 0, true, 0.91, 1)),
                List.of(new VideoAnalysis.Segment(0, 0.2, 1, 0.91)),
                "GkXfow==", "video/webm", "ok", 4200.0, null
        );
    }

    private static AiVideoPredictionResponse predictionAsFile(String modelType) {
        AiVideoPredictionResponse p = prediction(modelType);
        return new AiVideoPredictionResponse(
                p.success(), p.modelType(), p.originalFileName(), p.sourceFps(), p.sourceFrameCount(),
                p.durationSec(), p.width(), p.height(), p.sampleFps(), p.requestedSampleFps(),
                p.sampleRateReduced(), p.outputFps(), p.framesWritten(), p.framesHeld(), p.framesProcessed(),
                p.framesWithPolyp(), p.maxConfidence(), p.processingTimeMs(), p.averageInferenceMs(),
                p.throughputFps(), p.timeline(), p.segments(), "", "video/mp4", "ok", 4200.0,
                "0123456789abcdef0123456789abcdef"
        );
    }

    @Test
    void successfulAnalysisStoresFilesAndHistory() {
        MockMultipartFile video = mp4("clip.mp4");
        when(storageService.storeOriginal(eq(video), any(), eq("mp4"))).thenReturn("a.mp4");
        when(aiInferenceClient.predictVideo(video, "YOLO26s-TSVM-FP32-seg", 5))
                .thenReturn(prediction("YOLO26s-TSVM-FP32-seg"));
        when(storageService.storeResult(eq("GkXfow=="), any())).thenReturn("a_result.webm");
        when(repository.save(any())).thenAnswer(invocation -> invocation.getArgument(0));

        VideoAnalysis saved = service.analyze(video, "YOLO26s-TSVM-FP32-seg", 5, "user-id");

        ArgumentCaptor<VideoAnalysis> captor = ArgumentCaptor.forClass(VideoAnalysis.class);
        verify(repository).save(captor.capture());
        assertEquals(saved, captor.getValue());
        assertEquals("user-id", saved.getUserId());
        assertEquals(50, saved.getFramesProcessed());
        assertEquals(12, saved.getFramesWithPolyp());
        assertEquals(24.0, saved.getPositiveFramePercent(), 1e-9);
        assertEquals(4200.0, saved.getAiRoundTripMs(), 1e-9);
        assertEquals("a.mp4", saved.getOriginalVideoFile());
        assertEquals("a_result.webm", saved.getResultVideoFile());
        assertEquals(1, saved.getSegments().size());
        assertEquals(25.0, saved.getOutputFps(), 1e-9);
        assertEquals(200, saved.getFramesHeld());
        assertFalse(saved.isAllFrames());
    }

    @Test
    void allFramesModeIsAcceptedAndGpuRefusalIsExplained() {
        MockMultipartFile video = mp4("clip.mp4");
        when(storageService.storeOriginal(eq(video), any(), eq("mp4"))).thenReturn("a.mp4");
        when(aiInferenceClient.predictVideo(video, "YOLO26s-seg", VideoAnalysisService.ALL_FRAMES))
                .thenThrow(new AiServiceException("VIDEO_NEEDS_GPU", "Cần GPU."));

        DiagnosisOperationException error = assertThrows(DiagnosisOperationException.class,
                () -> service.analyze(video, "YOLO26s-seg", VideoAnalysisService.ALL_FRAMES, "user-id"));

        assertEquals("VIDEO_NEEDS_GPU", error.getCode());
        assertEquals(HttpStatus.UNPROCESSABLE_ENTITY, error.getStatus());
        assertEquals("Cần GPU.", error.getMessage());
    }

    @Test
    void rejectsUnsupportedSampleRateAndModel() {
        MockMultipartFile video = mp4("clip.mp4");
        assertEquals("INVALID_SAMPLE_FPS", assertThrows(DiagnosisOperationException.class,
                () -> service.analyze(video, "YOLO26s-seg", 7, "user-id")).getCode());
        assertEquals("INVALID_MODEL", assertThrows(DiagnosisOperationException.class,
                () -> service.analyze(video, "other", 5, "user-id")).getCode());
        verify(aiInferenceClient, never()).predictVideo(any(), anyString(), anyInt());
    }

    @Test
    void rejectsWrongExtensionAndSignature() {
        MockMultipartFile exe = new MockMultipartFile("video", "clip.exe", "video/mp4", new byte[64]);
        DiagnosisOperationException extension = assertThrows(DiagnosisOperationException.class,
                () -> service.analyze(exe, "YOLO26s-seg", 5, "user-id"));
        assertEquals(HttpStatus.UNSUPPORTED_MEDIA_TYPE, extension.getStatus());

        MockMultipartFile fake = new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[64]);
        assertEquals("SIGNATURE_MISMATCH", assertThrows(DiagnosisOperationException.class,
                () -> service.analyze(fake, "YOLO26s-seg", 5, "user-id")).getCode());
        verify(storageService, never()).storeOriginal(any(), any(), anyString());
    }

    @Test
    void containerSignaturesAreRecognised() {
        byte[] avi = "RIFF\0\0\0\0AVI LIST".getBytes();
        byte[] webm = {0x1a, 0x45, (byte) 0xdf, (byte) 0xa3, 0, 0, 0, 0, 0, 0, 0, 0};
        assertTrue(VideoAnalysisService.signatureMatches("avi", avi, avi.length));
        assertTrue(VideoAnalysisService.signatureMatches("webm", webm, webm.length));
        assertTrue(VideoAnalysisService.signatureMatches("mkv", webm, webm.length));
        assertFalse(VideoAnalysisService.signatureMatches("mp4", webm, webm.length));
    }

    @Test
    void aiFailureRollsBackOriginalAndNeverSaves() {
        MockMultipartFile video = mp4("clip.mp4");
        when(storageService.storeOriginal(eq(video), any(), eq("mp4"))).thenReturn("a.mp4");
        when(aiInferenceClient.predictVideo(video, "YOLO26s-seg", 5))
                .thenThrow(new AiServiceException("VIDEO_REJECTED", "Video quá dài."));

        DiagnosisOperationException error = assertThrows(DiagnosisOperationException.class,
                () -> service.analyze(video, "YOLO26s-seg", 5, "user-id"));

        assertEquals(HttpStatus.UNPROCESSABLE_ENTITY, error.getStatus());
        verify(storageService).deleteQuietly("a.mp4", null);
        verify(repository, never()).save(any());
    }

    @Test
    void ownersSeeTheirVideosAndAdminsSeeAll() {
        VideoAnalysis analysis = new VideoAnalysis();
        when(repository.findByIdAndUserId("v1", "user-id")).thenReturn(Optional.of(analysis));
        when(repository.findById("v1")).thenReturn(Optional.of(analysis));

        assertTrue(service.findAccessible("v1", "user-id", false).isPresent());
        assertTrue(service.findAccessible("v1", "admin-id", true).isPresent());
        assertTrue(service.findAccessible("", "user-id", false).isEmpty());
    }

    private static final String JOB = "0123456789abcdef0123456789abcdef";

    private VideoAnalysisService.LiveSession startedLive(MockMultipartFile video) {
        when(storageService.storeOriginal(eq(video), any(), eq("mp4"))).thenReturn("a.mp4");
        when(aiInferenceClient.startLiveVideo(video, "YOLO26s-seg", 5))
                .thenReturn(new com.polyp.polypweb.view.AiLiveVideoStart(JOB, "YOLO26s-seg", "clip.mp4", 5));
        return service.startLive(video, "YOLO26s-seg", 5, "user-id");
    }

    @Test
    void liveSessionStoresOriginalAndIsVisibleOnlyToItsOwner() {
        VideoAnalysisService.LiveSession session = startedLive(mp4("clip.mp4"));

        assertEquals(JOB, session.getJobId());
        assertTrue(service.findLive(JOB, "user-id", false).isPresent());
        assertTrue(service.findLive(JOB, "other-user", false).isEmpty());
        assertTrue(service.findLive(JOB, "admin-id", true).isPresent());
        assertTrue(service.findLive("unknown", "user-id", false).isEmpty());
        verify(aiInferenceClient, never()).predictVideo(any(), anyString(), anyInt());
    }

    @Test
    void liveStartFailureRemovesTheStoredOriginal() {
        MockMultipartFile video = mp4("clip.mp4");
        when(storageService.storeOriginal(eq(video), any(), eq("mp4"))).thenReturn("a.mp4");
        when(aiInferenceClient.startLiveVideo(video, "YOLO26s-seg", 5))
                .thenThrow(new AiServiceException("VIDEO_REJECTED", "Video quá dài."));

        assertThrows(DiagnosisOperationException.class,
                () -> service.startLive(video, "YOLO26s-seg", 5, "user-id"));
        verify(storageService).deleteQuietly("a.mp4", null);
    }

    @Test
    void liveResultSentAsFileIsDownloadedAndStreamedToStorage() {
        VideoAnalysisService.LiveSession session = startedLive(mp4("clip.mp4"));
        java.io.InputStream download = new java.io.ByteArrayInputStream(new byte[]{0, 0, 0, 24, 'f', 't', 'y', 'p'});
        when(aiInferenceClient.liveVideoStatus(JOB)).thenReturn(java.util.Map.of("state", "done"));
        when(aiInferenceClient.liveVideoResult(JOB, "YOLO26s-seg")).thenReturn(predictionAsFile("YOLO26s-seg"));
        when(aiInferenceClient.downloadResultVideo("0123456789abcdef0123456789abcdef")).thenReturn(download);
        when(storageService.storeResult(eq(download), any())).thenReturn("a_result.mp4");
        when(repository.save(any())).thenAnswer(invocation -> {
            VideoAnalysis analysis = invocation.getArgument(0);
            analysis.setId("video-2");
            return analysis;
        });

        assertEquals("saved", service.liveStatus(session).get("state"));
        verify(storageService, never()).storeResult(anyString(), any());
        ArgumentCaptor<VideoAnalysis> captor = ArgumentCaptor.forClass(VideoAnalysis.class);
        verify(repository).save(captor.capture());
        assertEquals("a_result.mp4", captor.getValue().getResultVideoFile());
    }

    @Test
    void finishedLiveSessionIsSavedExactlyOnce() {
        VideoAnalysisService.LiveSession session = startedLive(mp4("clip.mp4"));
        when(aiInferenceClient.liveVideoStatus(JOB)).thenReturn(java.util.Map.of("state", "running", "framesDone", 3));
        assertEquals("running", service.liveStatus(session).get("state"));
        verify(repository, never()).save(any());

        when(aiInferenceClient.liveVideoStatus(JOB)).thenReturn(java.util.Map.of("state", "done"));
        when(aiInferenceClient.liveVideoResult(JOB, "YOLO26s-seg")).thenReturn(prediction("YOLO26s-seg"));
        when(storageService.storeResult(eq("GkXfow=="), any())).thenReturn("a_result.mp4");
        when(repository.save(any())).thenAnswer(invocation -> {
            VideoAnalysis analysis = invocation.getArgument(0);
            analysis.setId("video-1");
            return analysis;
        });

        java.util.Map<String, Object> first = service.liveStatus(session);
        java.util.Map<String, Object> second = service.liveStatus(session);

        assertEquals("saved", first.get("state"));
        assertEquals("video-1", first.get("savedVideoId"));
        assertEquals("saved", second.get("state"));
        ArgumentCaptor<VideoAnalysis> captor = ArgumentCaptor.forClass(VideoAnalysis.class);
        verify(repository).save(captor.capture());
        assertEquals("a.mp4", captor.getValue().getOriginalVideoFile());
        assertEquals("a_result.mp4", captor.getValue().getResultVideoFile());
        assertEquals("user-id", captor.getValue().getUserId());
    }

    @Test
    void failedLiveSessionCleansUpAndReportsAnError() {
        VideoAnalysisService.LiveSession session = startedLive(mp4("clip.mp4"));
        when(aiInferenceClient.liveVideoStatus(JOB)).thenReturn(java.util.Map.of("state", "error"));

        java.util.Map<String, Object> status = service.liveStatus(session);

        assertEquals("error", status.get("state"));
        assertTrue(String.valueOf(status.get("error")).contains("không phân tích được"));
        verify(storageService).deleteQuietly("a.mp4", null);
        verify(repository, never()).save(any());
    }
}
