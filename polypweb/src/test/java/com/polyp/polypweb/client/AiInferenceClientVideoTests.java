package com.polyp.polypweb.client;

import com.polyp.polypweb.config.AiServiceProperties;
import com.polyp.polypweb.view.AiVideoPredictionResponse;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;
import tools.jackson.databind.json.JsonMapper;

import java.io.ByteArrayOutputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AiInferenceClientVideoTests {

    private static final String OK_JSON = """
            {"success":true,"modelType":"YOLO26s-seg","originalFileName":"clip.mp4","sourceFps":25,
             "sourceFrameCount":250,"durationSec":10,"width":640,"height":480,"sampleFps":5,
             "requestedSampleFps":5,"sampleRateReduced":false,"framesProcessed":50,"framesWithPolyp":3,
             "maxConfidence":0.9,"processingTimeMs":1000,"averageInferenceMs":20,"throughputFps":50,
             "timeline":[{"frameIndex":0,"timeSec":0,"detected":true,"confidence":0.9,"maskCount":1}],
             "segments":[{"startSec":0,"endSec":0.2,"frames":1,"maxConfidence":0.9}],
             "resultVideoBase64":"GkXfow==","resultVideoMimeType":"video/webm","message":"ok"}
            """;

    private HttpServer server;
    private final AtomicReference<String> contentLength = new AtomicReference<>();
    private final AtomicReference<String> transferEncoding = new AtomicReference<>();
    private final AtomicReference<byte[]> body = new AtomicReference<>();
    private volatile int status = 200;
    private volatile String reply = OK_JSON;

    @BeforeEach
    void startServer() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/video/predict", exchange -> {
            contentLength.set(exchange.getRequestHeaders().getFirst("Content-Length"));
            transferEncoding.set(exchange.getRequestHeaders().getFirst("Transfer-Encoding"));
            ByteArrayOutputStream received = new ByteArrayOutputStream();
            exchange.getRequestBody().transferTo(received);
            body.set(received.toByteArray());
            byte[] response = reply.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(status, response.length);
            try (OutputStream output = exchange.getResponseBody()) {
                output.write(response);
            }
        });
        server.createContext("/video/result/", exchange -> {
            byte[] video = {0x1a, 0x45, (byte) 0xdf, (byte) 0xa3, 1, 2, 3, 4};
            boolean known = exchange.getRequestURI().getPath().endsWith("/0123456789abcdef0123456789abcdef");
            exchange.getResponseHeaders().add("Content-Type", "video/webm");
            exchange.sendResponseHeaders(known ? 200 : 404, known ? video.length : -1);
            try (OutputStream output = exchange.getResponseBody()) {
                if (known) {
                    output.write(video);
                }
            }
        });
        server.start();
    }

    @AfterEach
    void stopServer() {
        server.stop(0);
    }

    private AiInferenceClient client() {
        AiServiceProperties properties = new AiServiceProperties();
        properties.setBaseUrl(URI.create("http://127.0.0.1:" + server.getAddress().getPort()));
        return new AiInferenceClient(
                HttpClient.newBuilder().version(HttpClient.Version.HTTP_1_1).build(),
                JsonMapper.builder().build(),
                properties
        );
    }

    @Test
    void resultVideoSentAsFileIsParsedAndDownloaded() throws Exception {
        reply = OK_JSON.replace("\"resultVideoBase64\":\"GkXfow==\"",
                "\"resultVideoBase64\":\"\",\"resultVideoId\":\"0123456789abcdef0123456789abcdef\"");
        MockMultipartFile file = new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[]{0, 0, 0, 8, 'f', 't', 'y', 'p'});

        AiVideoPredictionResponse response = client().predictVideo(file, "YOLO26s-seg", 0);

        assertTrue(response.resultVideoAsFile());
        try (java.io.InputStream video = client().downloadResultVideo(response.resultVideoId())) {
            assertEquals(8, video.readAllBytes().length);
        }
        AiServiceException missing = assertThrows(AiServiceException.class,
                () -> client().downloadResultVideo("ffffffffffffffffffffffffffffffff"));
        assertEquals("RESULT_VIDEO_NOT_FOUND", missing.getCode());
    }

    @Test
    void videoIsStreamedWithContentLengthAndAllFields() {
        byte[] video = new byte[300_000];
        video[4] = 'f';
        video[5] = 't';
        video[6] = 'y';
        video[7] = 'p';
        video[video.length - 1] = 42;
        MockMultipartFile file = new MockMultipartFile("video", "clip.mp4", "video/mp4", video);

        AiVideoPredictionResponse response = client().predictVideo(file, "YOLO26s-seg", 5);

        assertNotNull(contentLength.get(), "request must carry Content-Length, not chunked encoding");
        assertEquals(null, transferEncoding.get());
        assertEquals(body.get().length, Integer.parseInt(contentLength.get()));
        String text = new String(body.get(), StandardCharsets.ISO_8859_1);
        assertTrue(text.contains("name=\"video\"; filename=\"clip.mp4\""));
        assertTrue(text.contains("name=\"modelType\"\r\n\r\nYOLO26s-seg\r\n"));
        assertTrue(text.contains("name=\"resultVideoTransfer\"\r\n\r\nfile\r\n"));
        assertTrue(text.contains("name=\"sampleFps\"\r\n\r\n5\r\n"));
        assertTrue(body.get().length > video.length);
        assertEquals(50, response.framesProcessed());
        assertEquals(1, response.segments().size());
        assertNotNull(response.aiRoundTripMs());
    }

    @Test
    void rejectedVideoMapsToVideoRejected() {
        status = 422;
        reply = "{\"detail\":\"too long\"}";
        MockMultipartFile file = new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[16]);
        AiServiceException error = assertThrows(AiServiceException.class,
                () -> client().predictVideo(file, "YOLO26s-seg", 5));
        assertEquals("VIDEO_REJECTED", error.getCode());
    }

    @Test
    void allFramesOnCpuMapsToVideoNeedsGpu() {
        status = 422;
        reply = "{\"detail\":\"Analysing every frame needs the AI service to run on a GPU\"}";
        MockMultipartFile file = new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[16]);
        AiServiceException error = assertThrows(AiServiceException.class,
                () -> client().predictVideo(file, "YOLO26s-seg", 0));
        assertEquals("VIDEO_NEEDS_GPU", error.getCode());
        assertTrue(error.getMessage().contains("GPU"));
    }
}
