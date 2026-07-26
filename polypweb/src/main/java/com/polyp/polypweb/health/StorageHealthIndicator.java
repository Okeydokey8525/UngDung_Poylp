package com.polyp.polypweb.health;

import com.polyp.polypweb.service.FileStorageService;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

@Component("storage")
public class StorageHealthIndicator implements HealthIndicator {

    private final FileStorageService storageService;

    public StorageHealthIndicator(FileStorageService storageService) {
        this.storageService = storageService;
    }

    @Override
    public Health health() {
        try {
            storageService.verifyWritable();
            return Health.up()
                    .withDetail("writable", true)
                    .build();
        } catch (RuntimeException exception) {
            return Health.down()
                    .withDetail("writable", false)
                    .withDetail("reason", exception.getClass().getSimpleName())
                    .build();
        }
    }
}
