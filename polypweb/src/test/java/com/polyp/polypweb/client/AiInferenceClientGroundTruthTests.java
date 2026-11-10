package com.polyp.polypweb.client;

import com.polyp.polypweb.config.AiServiceProperties;
import com.polyp.polypweb.view.AiPredictionResponse;
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
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AiInferenceClientGroundTruthTests {

    private static final String BASE = """
            "success":true,"detected":true,"label":"polyp","confidence":0.9,"processingTimeMs":20,
            "maskCount":1,"modelType":"YOLO26s-seg","originalFileName":"a.jpg",
            "resultImageBase64":"/9j/","message":"ok\"""";
    private static final String WITH_METRICS = "{" + BASE + ",\"groundTruthMetrics\":{\"dice\":0.92,\"iou\":0.85,"
            + "\"precision\":0.98,\"recall\":0.87,\"truePositivePixels\":10,\"falsePositivePixels\":1,"
            + "\"falseNegativePixels\":2,\"groundTruthPixels\":12,\"predictedPixels\":11,\"imagePixels\":100,"
            + "\"backgroundImage\":false}}";

    private HttpServer server;
    private final AtomicReference<byte[]> body = new AtomicReference<>();
    private volatile int status = 200;
    private volatile String reply = WITH_METRICS;

    @BeforeEach
    void startServer() throws Exception {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/predict", exchange -> {
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

    private static MockMultipartFile image() {
        return new MockMultipartFile("image", "a.jpg", "image/jpeg", new byte[]{(byte) 0xff, (byte) 0xd8, 1});
    }

    private static MockMultipartFile mask() {
        return new MockMultipartFile("groundTruth", "a_mask.png", "image/png", new byte[]{(byte) 0x89, 'P', 'N', 'G'});
    }

    @Test
    void maskIsSentAsGroundTruthPartAndMetricsAreRead() {
        AiPredictionResponse response = client().predict(image(), mask(), "YOLO26s-seg");

        String text = new String(body.get(), StandardCharsets.ISO_8859_1);
        assertTrue(text.contains("name=\"groundTruth\"; filename=\"a_mask.png\""));
        assertTrue(text.contains("Content-Type: image/png"));
        assertEquals(0.92, response.getGroundTruthMetrics().getDice(), 1e-9);
        assertEquals(12, response.getGroundTruthMetrics().getGroundTruthPixels());
        assertFalse(response.getGroundTruthMetrics().isBackgroundImage());
    }

    @Test
    void withoutMaskNoPartIsSentAndMetricsAreIgnored() {
        AiPredictionResponse response = client().predict(image(), "YOLO26s-seg");

        assertFalse(new String(body.get(), StandardCharsets.ISO_8859_1).contains("groundTruth"));
        assertNull(response.getGroundTruthMetrics());
    }

    @Test
    void rejectedMaskMapsToGroundTruthRejected() {
        status = 422;
        reply = "{\"detail\":\"The ground-truth mask is 20x20 but the image is 13x7\"}";
        AiServiceException error = assertThrows(AiServiceException.class,
                () -> client().predict(image(), mask(), "YOLO26s-seg"));
        assertEquals("GROUND_TRUTH_REJECTED", error.getCode());
    }
}
