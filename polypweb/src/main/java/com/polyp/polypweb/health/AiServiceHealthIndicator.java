package com.polyp.polypweb.health;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceStatus;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.boot.health.contributor.Status;
import org.springframework.stereotype.Component;

@Component("aiService")
public class AiServiceHealthIndicator implements HealthIndicator {

    private static final Logger LOGGER = LoggerFactory.getLogger(AiServiceHealthIndicator.class);
    private final AiInferenceClient aiInferenceClient;

    public AiServiceHealthIndicator(AiInferenceClient aiInferenceClient) {
        this.aiInferenceClient = aiInferenceClient;
    }

    @Override
    public Health health() {
        try {
            AiServiceStatus status = aiInferenceClient.serviceStatus();
            Health.Builder builder = status.allModelsReady()
                    ? Health.up()
                    : Health.status(Status.OUT_OF_SERVICE);
            return builder
                    .withDetail("reachable", true)
                    .withDetail("baselineModel", readyLabel(status.baselineReady()))
                    .withDetail("vmambaModel", readyLabel(status.vmambaReady()))
                    .build();
        } catch (RuntimeException exception) {
            LOGGER.warn(
                    "FastAPI health không khả dụng: {}",
                    exception.getClass().getSimpleName()
            );
            return Health.down()
                    .withDetail("reachable", false)
                    .build();
        }
    }

    private String readyLabel(boolean ready) {
        return ready ? "ready" : "unavailable";
    }
}
