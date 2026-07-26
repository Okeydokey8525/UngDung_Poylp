package com.polyp.polypweb.config;

import com.polyp.polypweb.document.DiagnosisHistory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.stereotype.Component;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
public class DiagnosisHistoryIndexInitializer implements ApplicationRunner {

    private final MongoTemplate mongoTemplate;

    public DiagnosisHistoryIndexInitializer(MongoTemplate mongoTemplate) {
        this.mongoTemplate = mongoTemplate;
    }

    @Override
    public void run(ApplicationArguments args) {
        var indexOps = mongoTemplate.indexOps(DiagnosisHistory.class);
        indexOps.createIndex(new Index()
                .on("userId", Sort.Direction.ASC)
                .on("comparisonResult", Sort.Direction.ASC)
                .on("createdAt", Sort.Direction.DESC)
                .named("history_user_type_created"));
        indexOps.createIndex(new Index()
                .on("userId", Sort.Direction.ASC)
                .on("comparisonGroupId", Sort.Direction.ASC)
                .named("history_user_comparison_group"));
        indexOps.createIndex(new Index()
                .on("userId", Sort.Direction.ASC)
                .on("modelType", Sort.Direction.ASC)
                .on("createdAt", Sort.Direction.DESC)
                .named("history_user_model_created"));
        indexOps.createIndex(new Index()
                .on("userId", Sort.Direction.ASC)
                .on("detected", Sort.Direction.ASC)
                .on("createdAt", Sort.Direction.DESC)
                .named("history_user_detected_created"));
    }
}
