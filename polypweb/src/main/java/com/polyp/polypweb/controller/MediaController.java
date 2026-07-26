package com.polyp.polypweb.controller;

import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.security.CurrentUserPrincipal;
import com.polyp.polypweb.service.DiagnosisHistoryService;
import com.polyp.polypweb.service.FileStorageService;
import org.springframework.core.io.Resource;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.util.Optional;

@RestController
public class MediaController {

    private final DiagnosisHistoryService historyService;
    private final FileStorageService storageService;

    public MediaController(
            DiagnosisHistoryService historyService,
            FileStorageService storageService) {
        this.historyService = historyService;
        this.storageService = storageService;
    }

    @GetMapping("/diagnoses/{id}/original-image")
    public ResponseEntity<Resource> originalImage(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return media(id, principal, true);
    }

    @GetMapping("/diagnoses/{id}/result-image")
    public ResponseEntity<Resource> resultImage(
            @AuthenticationPrincipal CurrentUserPrincipal principal,
            @PathVariable String id) {
        return media(id, principal, false);
    }

    private ResponseEntity<Resource> media(
            String id,
            CurrentUserPrincipal principal,
            boolean original) {
        Optional<DiagnosisHistory> history = historyService.findDocumentAccessible(
                id,
                principal.getUserId(),
                principal.isAdmin()
        );
        if (history.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        String mediaUrl = original
                ? history.get().getOriginalImageUrl()
                : history.get().getResultImageUrl();
        return storageService.loadMediaUrl(mediaUrl)
                .map(resource -> ResponseEntity.ok()
                        .contentType(
                                mediaUrl != null && mediaUrl.endsWith(".png")
                                        ? MediaType.IMAGE_PNG
                                        : MediaType.IMAGE_JPEG
                        )
                        .cacheControl(CacheControl.maxAge(Duration.ofDays(1)).cachePrivate())
                        .body(resource))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }
}
