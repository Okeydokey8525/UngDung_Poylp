package com.polyp.polypweb.service;

import com.polyp.polypweb.controller.VideoController;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;
import java.util.Base64;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class VideoStorageServiceTests {

    @TempDir
    Path root;

    private static String b64(byte[] bytes) {
        return Base64.getEncoder().encodeToString(bytes);
    }

    @Test
    void mp4AndWebmResultsKeepTheirContainerExtension() {
        VideoStorageService storage = new VideoStorageService(root);
        UUID id = UUID.randomUUID();
        byte[] mp4 = {0, 0, 0, 24, 'f', 't', 'y', 'p', 'm', 'p', '4', '2'};
        byte[] webm = {0x1a, 0x45, (byte) 0xdf, (byte) 0xa3, 1, 2, 3, 4};

        String mp4Name = storage.storeResult(b64(mp4), id);
        String webmName = storage.storeResult(b64(webm), UUID.randomUUID());

        assertEquals(id + "_result.mp4", mp4Name);
        assertTrue(webmName.endsWith("_result.webm"));
        assertTrue(storage.loadResult(mp4Name).isPresent());
        assertTrue(storage.loadResult(webmName).isPresent());
        assertEquals("video/mp4", VideoController.resultType(mp4Name).toString());
        assertEquals("video/webm", VideoController.resultType(webmName).toString());
    }

    @Test
    void streamedResultIsWrittenWithoutBase64() throws Exception {
        VideoStorageService storage = new VideoStorageService(root);
        byte[] webm = new byte[200_000];
        webm[0] = 0x1a;
        webm[1] = 0x45;
        webm[2] = (byte) 0xdf;
        webm[3] = (byte) 0xa3;
        webm[webm.length - 1] = 7;

        String name = storage.storeResult(new java.io.ByteArrayInputStream(webm), UUID.randomUUID());

        assertTrue(name.endsWith("_result.webm"));
        assertEquals(webm.length, storage.loadResult(name).orElseThrow().contentLength());
        assertThrows(StorageException.class, () -> storage.storeResult(
                new java.io.ByteArrayInputStream("not a video at all".getBytes()), UUID.randomUUID()));
    }

    @Test
    void otherContentIsRejected() {
        VideoStorageService storage = new VideoStorageService(root);
        assertThrows(StorageException.class,
                () -> storage.storeResult(b64("not a video at all".getBytes()), UUID.randomUUID()));
    }
}
