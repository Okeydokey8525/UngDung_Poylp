package com.polyp.polypweb.health;

import com.polyp.polypweb.client.AiInferenceClient;
import com.polyp.polypweb.client.AiServiceException;
import com.polyp.polypweb.client.AiServiceStatus;
import com.polyp.polypweb.service.FileStorageService;
import com.polyp.polypweb.service.StorageException;
import org.junit.jupiter.api.Test;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.Status;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class HealthIndicatorTests {

    @Test
    void storageWritableIsUp() {
        FileStorageService storageService = mock(FileStorageService.class);
        Health health = new StorageHealthIndicator(storageService).health();

        assertThat(health.getStatus()).isEqualTo(Status.UP);
        assertThat(health.getDetails()).containsEntry("writable", true);
    }

    @Test
    void storageNotWritableIsDownWithoutPathDisclosure() {
        FileStorageService storageService = mock(FileStorageService.class);
        doThrow(new StorageException("C:\\sensitive\\storage"))
                .when(storageService).verifyWritable();

        Health health = new StorageHealthIndicator(storageService).health();

        assertThat(health.getStatus()).isEqualTo(Status.DOWN);
        assertThat(health.getDetails())
                .containsEntry("writable", false)
                .doesNotContainValue("C:\\sensitive\\storage");
    }

    @Test
    void bothModelsReadyIsUp() {
        AiInferenceClient client = mock(AiInferenceClient.class);
        when(client.serviceStatus()).thenReturn(new AiServiceStatus(true, true));

        Health health = new AiServiceHealthIndicator(client).health();

        assertThat(health.getStatus()).isEqualTo(Status.UP);
        assertThat(health.getDetails())
                .containsEntry("baselineModel", "ready")
                .containsEntry("vmambaModel", "ready");
    }

    @Test
    void oneModelUnavailableIsOutOfService() {
        AiInferenceClient client = mock(AiInferenceClient.class);
        when(client.serviceStatus()).thenReturn(new AiServiceStatus(true, false));

        Health health = new AiServiceHealthIndicator(client).health();

        assertThat(health.getStatus()).isEqualTo(Status.OUT_OF_SERVICE);
        assertThat(health.getDetails())
                .containsEntry("reachable", true)
                .containsEntry("vmambaModel", "unavailable");
    }

    @Test
    void fastApiUnavailableIsDownWithoutUrlOrCheckpointDisclosure() {
        AiInferenceClient client = mock(AiInferenceClient.class);
        when(client.serviceStatus())
                .thenThrow(new AiServiceException("http://secret-ai/checkpoint/C:\\models\\best.pt"));

        Health health = new AiServiceHealthIndicator(client).health();

        assertThat(health.getStatus()).isEqualTo(Status.DOWN);
        assertThat(health.getDetails())
                .containsEntry("reachable", false)
                .doesNotContainValue("http://secret-ai/checkpoint/C:\\models\\best.pt");
    }
}
