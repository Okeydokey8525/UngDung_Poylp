package com.polyp.polypweb.repository;

import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.view.filter.ComparisonHistoryFilter;
import org.bson.Document;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.aggregation.Aggregation;
import org.springframework.data.mongodb.core.aggregation.AggregationOperation;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.stereotype.Repository;

import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;

@Repository
public class ComparisonHistorySearchRepository {

    private static final Logger LOGGER =
            LoggerFactory.getLogger(ComparisonHistorySearchRepository.class);
    private static final String COLLECTION = "diagnosis_history";
    private static final ZoneId APPLICATION_ZONE = ZoneId.of("Asia/Ho_Chi_Minh");

    private final MongoTemplate mongoTemplate;

    public ComparisonHistorySearchRepository(MongoTemplate mongoTemplate) {
        this.mongoTemplate = mongoTemplate;
    }

    public Page<ComparisonHistoryRecord> search(
            String userId,
            ComparisonHistoryFilter filter) {
        List<AggregationOperation> operations = List.of(
                Aggregation.match(new Criteria().andOperator(
                        Criteria.where("userId").is(userId),
                        Criteria.where("comparisonResult").is(true),
                        Criteria.where("comparisonGroupId").type(2).ne("")
                )),
                context -> new Document("$group", groupDocument()),
                context -> new Document("$set", new Document("validGroup", validGroupExpression())),
                context -> new Document("$facet", outerFacet(filter))
        );

        Document result = mongoTemplate.aggregate(
                        Aggregation.newAggregation(operations),
                        COLLECTION,
                        Document.class
                )
                .getUniqueMappedResult();
        if (result == null) {
            return Page.empty(PageRequest.of(filter.getPageIndex(), filter.getPageSize()));
        }

        long invalidGroups = countFromFacet(result, "invalidGroups");
        if (invalidGroups > 0) {
            LOGGER.warn(
                    "Bỏ qua {} phiên so sánh không hoàn chỉnh hoặc không nhất quán của user {}",
                    invalidGroups,
                    userId
            );
        }

        long total = countFromFacet(result, "metadata");
        List<ComparisonHistoryRecord> records = documents(result, "data")
                .stream()
                .map(this::toRecord)
                .toList();
        PageRequest pageable = PageRequest.of(filter.getPageIndex(), filter.getPageSize());
        return new PageImpl<>(records, pageable, total);
    }

    private Document groupDocument() {
        Object baselineCondition = new Document(
                "$eq",
                List.of("$modelType", ModelComparisonService.BASELINE_MODEL)
        );
        Object vmambaCondition = new Document(
                "$eq",
                List.of("$modelType", ModelComparisonService.VMAMBA_MODEL)
        );
        return new Document("_id", "$comparisonGroupId")
                .append("totalDocuments", new Document("$sum", 1))
                .append("baselineCount", sumWhen(baselineCondition))
                .append("vmambaCount", sumWhen(vmambaCondition))
                .append(
                        "baseline",
                        new Document(
                                "$max",
                                new Document(
                                        "$cond",
                                        Arrays.asList(baselineCondition, "$$ROOT", null)
                                )
                        )
                )
                .append(
                        "vmamba",
                        new Document(
                                "$max",
                                new Document(
                                        "$cond",
                                        Arrays.asList(vmambaCondition, "$$ROOT", null)
                                )
                        )
                )
                .append("fileNames", new Document("$addToSet", "$fileName"))
                .append("originalImageUrls", new Document("$addToSet", "$originalImageUrl"))
                .append("createdAt", new Document("$max", "$createdAt"));
    }

    private Document validGroupExpression() {
        return new Document("$and", List.of(
                new Document("$eq", List.of("$totalDocuments", 2)),
                new Document("$eq", List.of("$baselineCount", 1)),
                new Document("$eq", List.of("$vmambaCount", 1)),
                new Document("$eq", List.of(new Document("$size", "$fileNames"), 1)),
                new Document("$eq", List.of(new Document("$size", "$originalImageUrls"), 1))
        ));
    }

    private Document outerFacet(ComparisonHistoryFilter filter) {
        List<Document> records = new ArrayList<>();
        records.add(new Document("$match", new Document("validGroup", true)));
        records.add(new Document("$project", new Document("_id", 0)
                .append("comparisonGroupId", "$_id")
                .append("fileName", new Document("$arrayElemAt", List.of("$fileNames", 0)))
                .append("createdAt", 1)
                .append("baseline", 1)
                .append("vmamba", 1)
                .append(
                        "totalProcessingTimeMs",
                        new Document("$add", List.of(
                                new Document("$ifNull", List.of("$baseline.processingTimeMs", 0)),
                                new Document("$ifNull", List.of("$vmamba.processingTimeMs", 0))
                        ))
                )));
        records.add(new Document("$match", filterMatch(filter)));

        // MongoDB forbids nesting $facet. Count and page the same filtered groups
        // in sibling branches so the total remains independent of pagination.
        List<Document> metadata = new ArrayList<>(records);
        metadata.add(new Document("$count", "count"));
        List<Document> data = new ArrayList<>(records);
        data.add(new Document("$sort", new Document(
                filter.getSortOption().getField(),
                filter.getSortOption().getDirection()
        ).append("comparisonGroupId", 1)));
        data.add(new Document("$skip", (long) filter.getPageIndex() * filter.getPageSize()));
        data.add(new Document("$limit", filter.getPageSize()));

        return new Document()
                .append("invalidGroups", List.of(
                        new Document("$match", new Document("validGroup", false)),
                        new Document("$count", "count")
                ))
                .append("metadata", metadata)
                .append("data", data);
    }

    private Document filterMatch(ComparisonHistoryFilter filter) {
        Document match = new Document();
        if (!filter.getKeyword().isBlank()) {
            match.append(
                    "fileName",
                    Pattern.compile(
                            Pattern.quote(filter.getKeyword()),
                            Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE
                    )
            );
        }
        if (!filter.getBaselineDetectionOption().isAll()) {
            match.append(
                    "baseline.detected",
                    filter.getBaselineDetectionOption().getDetected()
            );
        }
        if (!filter.getVmambaDetectionOption().isAll()) {
            match.append(
                    "vmamba.detected",
                    filter.getVmambaDetectionOption().getDetected()
            );
        }
        if (filter.getParsedDateFrom() != null || filter.getParsedDateTo() != null) {
            Document date = new Document();
            if (filter.getParsedDateFrom() != null) {
                date.append(
                        "$gte",
                        java.util.Date.from(
                                filter.getParsedDateFrom()
                                        .atStartOfDay(APPLICATION_ZONE)
                                        .toInstant()
                        )
                );
            }
            if (filter.getParsedDateTo() != null) {
                date.append(
                        "$lt",
                        java.util.Date.from(
                                filter.getParsedDateTo()
                                        .plusDays(1)
                                        .atStartOfDay(APPLICATION_ZONE)
                                        .toInstant()
                        )
                );
            }
            match.append("createdAt", date);
        }
        return match;
    }

    private Document sumWhen(Object condition) {
        return new Document("$sum", new Document("$cond", List.of(condition, 1, 0)));
    }

    private ComparisonHistoryRecord toRecord(Document document) {
        DiagnosisHistory baseline = mongoTemplate.getConverter().read(
                DiagnosisHistory.class,
                document.get("baseline", Document.class)
        );
        DiagnosisHistory vmamba = mongoTemplate.getConverter().read(
                DiagnosisHistory.class,
                document.get("vmamba", Document.class)
        );
        java.util.Date createdAt = document.getDate("createdAt");
        return new ComparisonHistoryRecord(
                document.getString("comparisonGroupId"),
                document.getString("fileName"),
                createdAt == null
                        ? null
                        : createdAt.toInstant().atZone(APPLICATION_ZONE).toLocalDateTime(),
                number(document, "totalProcessingTimeMs").doubleValue(),
                baseline,
                vmamba
        );
    }

    private long countFromFacet(Document document, String key) {
        Document count = firstDocument(document, key);
        return number(count, "count").longValue();
    }

    private Document firstDocument(Document result, String key) {
        List<Document> values = documents(result, key);
        return values.isEmpty() ? new Document() : values.get(0);
    }

    @SuppressWarnings("unchecked")
    private List<Document> documents(Document result, String key) {
        Object value = result.get(key);
        return value instanceof List<?> list ? (List<Document>) list : List.of();
    }

    private Number number(Document document, String key) {
        Object value = document.get(key);
        return value instanceof Number number ? number : 0;
    }
}
