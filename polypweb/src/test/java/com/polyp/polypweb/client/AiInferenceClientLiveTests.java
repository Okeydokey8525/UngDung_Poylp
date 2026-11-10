package com.polyp.polypweb.client;

import com.polyp.polypweb.config.AiServiceProperties;
import com.polyp.polypweb.view.AiLiveVideoStart;
import com.polyp.polypweb.view.AiVideoPredictionResponse;
import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;
import tools.jackson.databind.json.JsonMapper;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AiInferenceClientLiveTests {

    private static final String JOB = "0123456789abcdef0123456789abcdef";
    private static final String RESULT = """
            {"success":true,"modelType":"YOLO26s-seg","originalFileName":"clip.mp4","sourceFps":25,
             "sourceFrameCount":250,"durationSec":10,"width":640,"height":480,"sampleFps":5,
             "requestedSampleFps":5,"sampleRateReduced":false,"outputFps":25,"framesWritten":250,
             "framesHeld":200,"framesProcessed":50,"framesWithPolyp":3,
             "maxConfidence":0.9,"processingTimeMs":10000,"averageInferenceMs":20,"throughputFps":5,
             "timeline":[{"frameIndex":0,"timeSec":0,"detected":true,"confidence":0.9,"maskCount":1}],
             "segments":[{"startSec":0,"endSec":0.2,"frames":1,"maxConfidence":0.9}],
             "resultVideoBase64":"AAAAGGZ0eXA=","resultVideoMimeType":"video/mp4","message":"ok"}
            """;
    private static final byte[] STREAM = "--polypframe\r\nContent-Type: image/jpeg\r\n\r\nJPEG\r\n"
            .getBytes(StandardCharsets.US_ASCII);

    private HttpServer server;
    private volatile int resultStatus = 200;
    private volatile String lastPath;

    @BeforeEach
    void startServer() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/video/live", exchange -> {
            String path = exchange.getRequestURI().getPath();
            lastPath = path;
            exchange.getRequestBody().readAllBytes();
            int status = 200;
            String type = "application/json";
            byte[] body;
            if (path.equals("/video/live")) {
                status = 202;
                body = ("{\"jobId\":\"" + JOB + "\",\"modelType\":\"YOLO26s-seg\",\"originalFileName\":\"clip.mp4\","
                        + "\"requestedSampleFps\":5}").getBytes(StandardCharsets.UTF_8);
            } else if (path.endsWith("/status")) {
                body = "{\"state\":\"running\",\"framesDone\":12,\"realtimeFactor\":0.98}".getBytes(StandardCharsets.UTF_8);
            } else if (path.endsWith("/stream")) {
                type = "multipart/x-mixed-replace; boundary=polypframe";
                body = STREAM;
            } else {
                status = resultStatus;
                body = (status == 200 ? RESULT : "{\"detail\":\"still running\"}").getBytes(StandardCharsets.UTF_8);
            }
            exchange.getResponseHeaders().add("Content-Type", type);
            exchange.sendResponseHeaders(status, body.length);
            try (OutputStream output = exchange.getResponseBody()) {
                output.write(body);
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
    void startStatusStreamAndResultFollowTheLiveJob() throws Exception {
        MockMultipartFile file = new MockMultipartFile("video", "clip.mp4", "video/mp4", new byte[64]);
        AiLiveVideoStart start = client().startLiveVideo(file, "YOLO26s-seg", 5);
        assertEquals(JOB, start.jobId());

        Map<String, Object> status = client().liveVideoStatus(JOB);
        assertEquals("running", status.get("state"));
        assertEquals(12, ((Number) status.get("framesDone")).intValue());

        HttpResponse<InputStream> stream = client().openLiveVideoStream(JOB);
        assertTrue(stream.headers().firstValue("Content-Type").orElse("").startsWith("multipart/x-mixed-replace"));
        try (InputStream input = stream.body()) {
            assertArrayEquals(STREAM, input.readAllBytes());
        }

        AiVideoPredictionResponse result = client().liveVideoResult(JOB, "YOLO26s-seg");
        assertEquals(50, result.framesProcessed());
        assertEquals("/video/live/" + JOB + "/result", lastPath);
    }

    @Test
    void runningJobAndInvalidIdsAreReported() {
        resultStatus = 409;
        assertEquals("LIVE_RUNNING", assertThrows(AiServiceException.class,
                () -> client().liveVideoResult(JOB, "YOLO26s-seg")).getCode());
        assertEquals("LIVE_NOT_FOUND", assertThrows(AiServiceException.class,
                () -> client().liveVideoStatus("../../predict")).getCode());
    }
}
