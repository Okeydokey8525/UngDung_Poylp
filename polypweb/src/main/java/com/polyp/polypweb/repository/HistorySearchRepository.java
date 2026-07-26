package com.polyp.polypweb.repository;

import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.view.filter.HistoryFilter;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.stereotype.Repository;

import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

@Repository
public class HistorySearchRepository {

    private static final ZoneId APPLICATION_ZONE = ZoneId.of("Asia/Ho_Chi_Minh");

    private final MongoTemplate mongoTemplate;

    public HistorySearchRepository(MongoTemplate mongoTemplate) {
        this.mongoTemplate = mongoTemplate;
    }

    public Page<DiagnosisHistory> search(String userId, HistoryFilter filter) {
        Criteria criteria = criteria(userId, filter);
        long total = mongoTemplate.count(new Query(criteria), DiagnosisHistory.class);
        PageRequest pageable = PageRequest.of(
                filter.getPageIndex(),
                filter.getPageSize(),
                filter.getSortOption().toSort()
        );
        Query query = new Query(criteria).with(pageable);
        List<DiagnosisHistory> items = mongoTemplate.find(query, DiagnosisHistory.class);
        return new PageImpl<>(items, pageable, total);
    }

    private Criteria criteria(String userId, HistoryFilter filter) {
        List<Criteria> criteria = new ArrayList<>();
        criteria.add(Criteria.where("userId").is(userId));
        criteria.add(new Criteria().orOperator(
                Criteria.where("comparisonResult").is(false),
                Criteria.where("comparisonResult").is(null)
        ));

        if (!filter.getKeyword().isBlank()) {
            Pattern escapedKeyword = Pattern.compile(
                    Pattern.quote(filter.getKeyword()),
                    Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE
            );
            criteria.add(Criteria.where("fileName").regex(escapedKeyword));
        }
        if (!filter.getModelOption().isAll()) {
            criteria.add(Criteria.where("modelType").is(filter.getModelOption().getModelType()));
        }
        if (!filter.getDetectionOption().isAll()) {
            criteria.add(Criteria.where("detected").is(filter.getDetectionOption().getDetected()));
        }
        if (filter.getParsedDateFrom() != null || filter.getParsedDateTo() != null) {
            Criteria createdAt = Criteria.where("createdAt");
            if (filter.getParsedDateFrom() != null) {
                createdAt.gte(filter.getParsedDateFrom().atStartOfDay(APPLICATION_ZONE).toInstant());
            }
            if (filter.getParsedDateTo() != null) {
                createdAt.lt(
                        filter.getParsedDateTo()
                                .plusDays(1)
                                .atStartOfDay(APPLICATION_ZONE)
                                .toInstant()
                );
            }
            criteria.add(createdAt);
        }
        return new Criteria().andOperator(criteria);
    }
}
