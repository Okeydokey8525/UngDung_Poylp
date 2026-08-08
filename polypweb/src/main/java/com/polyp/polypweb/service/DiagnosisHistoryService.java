package com.polyp.polypweb.service;

import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.HistorySearchRepository;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.filter.HistoryFilter;
import org.springframework.data.domain.Page;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.stereotype.Service;

import java.util.Optional;

@Service
public class DiagnosisHistoryService {

    private final DiagnosisHistoryRepository repository;
    private final HistorySearchRepository searchRepository;
    private final FileStorageService storageService;

    public DiagnosisHistoryService(
            DiagnosisHistoryRepository repository,
            HistorySearchRepository searchRepository,
            FileStorageService storageService) {
        this.repository = repository;
        this.searchRepository = searchRepository;
        this.storageService = storageService;
    }

    public DiagnosisResultView saveResult(DiagnosisResultView result, String userId) {
        DiagnosisHistory history = new DiagnosisHistory(
                userId,
                result.getFileName(),
                result.getModelType(),
                result.isDetected(),
                result.getLabel(),
                result.getConfidence(),
                result.getProcessingTimeMs(),
                result.getMaskCount(),
                result.getOriginalImageUrl(),
                result.getResultImageUrl(),
                result.getCreatedAt(),
                null,
                false
        );
        return toView(repository.save(history));
    }

    public Page<DiagnosisResultView> findHistoryPage(
            String userId,
            HistoryFilter filter) {
        return searchRepository.search(userId, filter).map(this::toView);
    }

    public Optional<DiagnosisResultView> findByIdAccessible(
            String id,
            String userId,
            boolean admin) {
        return findDocumentAccessible(id, userId, admin)
                .filter(history -> !history.isComparisonResult())
                .map(this::toView);
    }

    public Optional<DiagnosisHistory> findDocumentAccessible(
            String id,
            String userId,
            boolean admin) {
        Optional<DiagnosisHistory> accessible = admin
                ? repository.findById(id)
                : repository.findByIdAndUserId(id, userId);
        if (accessible.isEmpty() && !admin && repository.existsById(id)) {
            throw new AccessDeniedException("Bạn không có quyền truy cập kết quả này.");
        }
        return accessible;
    }

    public boolean deleteAccessible(String id, String userId, boolean admin) {
        Optional<DiagnosisHistory> accessible = findDocumentAccessible(id, userId, admin)
                .filter(history -> !history.isComparisonResult());
        if (accessible.isEmpty()) {
            return false;
        }

        DiagnosisHistory history = accessible.get();
        if (admin) {
            repository.deleteById(history.getId());
        } else {
            long deleted = repository.deleteByIdAndUserId(history.getId(), userId);
            if (deleted == 0) {
                return false;
            }
        }
        storageService.deleteQuietly(history.getOriginalImageUrl());
        storageService.deleteQuietly(history.getResultImageUrl());
        return true;
    }

    public DiagnosisResultView toView(DiagnosisHistory history) {
        return new DiagnosisResultView(
                history.getId(),
                "/diagnoses/" + history.getId() + "/original-image",
                "/diagnoses/" + history.getId() + "/result-image",
                history.getFileName(),
                history.getModelType(),
                history.isDetected(),
                history.getLabel(),
                history.getConfidence(),
                history.getProcessingTimeMs(),
                history.getMaskCount(),
                "1280 × 720 px",
                history.getCreatedAt(),
                true,
                history.getComparisonGroupId(),
                history.isComparisonResult()
        );
    }
}
