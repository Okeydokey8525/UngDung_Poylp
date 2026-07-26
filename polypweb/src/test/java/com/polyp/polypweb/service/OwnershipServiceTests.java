package com.polyp.polypweb.service;

import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.repository.DiagnosisHistoryRepository;
import com.polyp.polypweb.repository.HistorySearchRepository;
import com.polyp.polypweb.view.DiagnosisResultView;
import com.polyp.polypweb.view.filter.HistoryFilter;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.security.access.AccessDeniedException;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class OwnershipServiceTests {

    private static final String USER_A = "user-a";
    private static final String USER_B = "user-b";

    @Mock
    private DiagnosisHistoryRepository repository;
    @Mock
    private HistorySearchRepository searchRepository;
    @Mock
    private FileStorageService storageService;

    private DiagnosisHistoryService service;

    @BeforeEach
    void setUp() {
        service = new DiagnosisHistoryService(repository, searchRepository, storageService);
    }

    @Test
    void userCannotViewAnotherUsersDiagnosis() {
        when(repository.findByIdAndUserId("diagnosis-b", USER_A)).thenReturn(Optional.empty());
        when(repository.existsById("diagnosis-b")).thenReturn(true);

        assertThrows(
                AccessDeniedException.class,
                () -> service.findByIdAccessible("diagnosis-b", USER_A, false)
        );
    }

    @Test
    void userCannotDeleteAnotherUsersDiagnosisOrFiles() {
        when(repository.findByIdAndUserId("diagnosis-b", USER_A)).thenReturn(Optional.empty());
        when(repository.existsById("diagnosis-b")).thenReturn(true);

        assertThrows(
                AccessDeniedException.class,
                () -> service.deleteAccessible("diagnosis-b", USER_A, false)
        );
        verify(repository, never()).deleteById(any());
        verify(repository, never()).deleteByIdAndUserId(any(), any());
        verify(storageService, never()).deleteQuietly(any());
    }

    @Test
    void ownerCanViewMediaMetadataThroughSecureDiagnosisId() {
        DiagnosisHistory history = singleHistory("diagnosis-a", USER_A);
        when(repository.findByIdAndUserId("diagnosis-a", USER_A)).thenReturn(Optional.of(history));

        Optional<DiagnosisHistory> found =
                service.findDocumentAccessible("diagnosis-a", USER_A, false);

        assertTrue(found.isPresent());
        assertEquals("/media/original/" + id() + ".jpg", found.get().getOriginalImageUrl());
    }

    @Test
    void ownerDeleteRemovesDocumentThenItsTwoFiles() {
        DiagnosisHistory history = singleHistory("diagnosis-a", USER_A);
        when(repository.findByIdAndUserId("diagnosis-a", USER_A)).thenReturn(Optional.of(history));
        when(repository.deleteByIdAndUserId("diagnosis-a", USER_A)).thenReturn(1L);

        assertTrue(service.deleteAccessible("diagnosis-a", USER_A, false));

        verify(storageService).deleteQuietly(history.getOriginalImageUrl());
        verify(storageService).deleteQuietly(history.getResultImageUrl());
    }

    @Test
    void adminCanViewAndDeleteAnyDiagnosisByExplicitRolePath() {
        DiagnosisHistory history = singleHistory("diagnosis-b", USER_B);
        when(repository.findById("diagnosis-b")).thenReturn(Optional.of(history));

        assertTrue(service.findByIdAccessible("diagnosis-b", "admin-id", true).isPresent());
        assertTrue(service.deleteAccessible("diagnosis-b", "admin-id", true));

        verify(repository).deleteById("diagnosis-b");
    }

    @Test
    void historyQueryIsScopedAtRepositoryByCurrentUserId() {
        HistoryFilter filter = new HistoryFilter().normalize();
        when(searchRepository.search(USER_A, filter))
                .thenReturn(new PageImpl<>(List.of(singleHistory("diagnosis-a", USER_A))));

        Page<DiagnosisResultView> history = service.findHistoryPage(USER_A, filter);

        assertEquals(1, history.getTotalElements());
        verify(searchRepository).search(USER_A, filter);
    }

    @Test
    void savedDiagnosisUsesAuthenticatedUserIdArgument() {
        DiagnosisResultView input = new DiagnosisResultView(
                null,
                "/media/original/" + id() + ".jpg",
                "/media/results/" + id() + "_result.jpg",
                "sample.jpg",
                "YOLO26n-seg",
                true,
                "polyp",
                91,
                100,
                1,
                "1280 × 720 px",
                LocalDateTime.now(),
                false,
                null,
                false
        );
        when(repository.save(any(DiagnosisHistory.class))).thenAnswer(invocation -> {
            DiagnosisHistory history = invocation.getArgument(0);
            history.setId("new-id");
            return history;
        });

        DiagnosisResultView saved = service.saveResult(input, USER_A);

        assertEquals("new-id", saved.getId());
        verify(repository).save(org.mockito.ArgumentMatchers.argThat(
                history -> USER_A.equals(history.getUserId())
        ));
    }

    @Test
    void missingDiagnosisDoesNotDeleteAnything() {
        when(repository.findByIdAndUserId("missing", USER_A)).thenReturn(Optional.empty());
        when(repository.existsById("missing")).thenReturn(false);

        assertFalse(service.deleteAccessible("missing", USER_A, false));
        verify(storageService, never()).deleteQuietly(any());
    }

    private DiagnosisHistory singleHistory(String documentId, String userId) {
        DiagnosisHistory history = new DiagnosisHistory(
                userId,
                "sample.jpg",
                "YOLO26n-seg",
                true,
                "polyp",
                91,
                100,
                1,
                "/media/original/" + id() + ".jpg",
                "/media/results/" + id() + "_result.jpg",
                LocalDateTime.now(),
                null,
                false
        );
        history.setId(documentId);
        return history;
    }

    private String id() {
        return "11111111-1111-1111-1111-111111111111";
    }
}
