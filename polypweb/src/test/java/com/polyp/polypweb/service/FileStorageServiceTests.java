package com.polyp.polypweb.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;
import java.nio.file.Files;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.assertFalse;

class FileStorageServiceTests {

    @TempDir
    private Path temporaryDirectory;

    @Test
    void traversalAndUnapprovedStorageNamesAreRejected() {
        FileStorageService service = new FileStorageService(temporaryDirectory.toString());

        assertTrue(service.loadMediaUrl("/media/original/../../secret.txt").isEmpty());
        assertTrue(service.loadMediaUrl("/media/results/..\\secret.jpg").isEmpty());
        assertTrue(service.loadMediaUrl("/media/private/file.jpg").isEmpty());
        assertTrue(service.loadMediaUrl("C:\\secret.jpg").isEmpty());
    }

    @Test
    void writableHealthProbeIsDeletedImmediately() throws Exception {
        FileStorageService service = new FileStorageService(temporaryDirectory.toString());

        service.verifyWritable();

        try (var paths = Files.walk(temporaryDirectory)) {
            assertFalse(paths.anyMatch(path -> path.getFileName().toString().startsWith(".health-")));
        }
    }
}
