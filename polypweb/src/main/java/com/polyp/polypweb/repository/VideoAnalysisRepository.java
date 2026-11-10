package com.polyp.polypweb.repository;

import com.polyp.polypweb.document.VideoAnalysis;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.Optional;

public interface VideoAnalysisRepository extends MongoRepository<VideoAnalysis, String> {

    Optional<VideoAnalysis> findByIdAndUserId(String id, String userId);

    Page<VideoAnalysis> findAllByUserIdOrderByCreatedAtDesc(String userId, Pageable pageable);
}
