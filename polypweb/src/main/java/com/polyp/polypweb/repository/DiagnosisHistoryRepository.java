package com.polyp.polypweb.repository;

import com.polyp.polypweb.document.DiagnosisHistory;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.List;
import java.util.Optional;

public interface DiagnosisHistoryRepository extends MongoRepository<DiagnosisHistory, String> {

    List<DiagnosisHistory> findAllByUserId(String userId);

    long countByUserId(String userId);

    List<DiagnosisHistory> findTop20ByUserIdOrderByCreatedAtDesc(String userId);

    List<DiagnosisHistory> findTop20ByOrderByCreatedAtDesc();

    List<DiagnosisHistory> findAllByComparisonGroupIdAndUserIdOrderByCreatedAtAsc(
            String comparisonGroupId,
            String userId
    );

    List<DiagnosisHistory> findAllByComparisonGroupIdOrderByCreatedAtAsc(String comparisonGroupId);

    Optional<DiagnosisHistory> findByIdAndUserId(String id, String userId);

    long deleteByIdAndUserId(String id, String userId);

    long deleteAllByComparisonGroupIdAndUserId(String comparisonGroupId, String userId);
}
