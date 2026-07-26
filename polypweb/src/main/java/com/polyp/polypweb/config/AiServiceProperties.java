package com.polyp.polypweb.config;

import jakarta.validation.constraints.NotNull;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.net.URI;
import java.time.Duration;

@Validated
@ConfigurationProperties(prefix = "ai.api")
public class AiServiceProperties {

    @NotNull
    private URI baseUrl;

    @NotNull
    private Duration connectTimeout = Duration.ofSeconds(3);

    @NotNull
    private Duration readTimeout = Duration.ofSeconds(15);

    @NotNull
    private Duration healthTimeout = Duration.ofSeconds(2);

    public URI getBaseUrl() {
        return baseUrl;
    }

    public void setBaseUrl(URI baseUrl) {
        this.baseUrl = baseUrl;
    }

    public Duration getConnectTimeout() {
        return connectTimeout;
    }

    public void setConnectTimeout(Duration connectTimeout) {
        this.connectTimeout = requirePositive(connectTimeout, "connect-timeout");
    }

    public Duration getReadTimeout() {
        return readTimeout;
    }

    public void setReadTimeout(Duration readTimeout) {
        this.readTimeout = requirePositive(readTimeout, "read-timeout");
    }

    public Duration getHealthTimeout() {
        return healthTimeout;
    }

    public void setHealthTimeout(Duration healthTimeout) {
        this.healthTimeout = requirePositive(healthTimeout, "health-timeout");
    }

    private Duration requirePositive(Duration value, String name) {
        if (value == null || value.isZero() || value.isNegative()) {
            throw new IllegalArgumentException("ai.api." + name + " phải lớn hơn 0.");
        }
        return value;
    }
}
