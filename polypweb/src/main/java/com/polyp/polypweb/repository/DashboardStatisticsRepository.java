package com.polyp.polypweb.repository;

import org.bson.Document;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.aggregation.Aggregation;
import org.springframework.data.mongodb.core.aggregation.AggregationOperation;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Repository
public class DashboardStatisticsRepository {

    private static final String COLLECTION = "diagnosis_history";
    private static final String BASELINE_MODEL = "YOLO26n-seg";
    private static final String VMAMBA_MODEL = "YOLO26n-VMamba-seg";
    private static final ZoneId DASHBOARD_ZONE = ZoneId.of("Asia/Ho_Chi_Minh");

    private final MongoTemplate mongoTemplate;

    public DashboardStatisticsRepository(MongoTemplate mongoTemplate) {
        this.mongoTemplate = mongoTemplate;
    }

    public DashboardStatisticsSnapshot aggregate(String userId, int days) {
        LocalDate firstDay = LocalDate.now(DASHBOARD_ZONE).minusDays(days - 1L);
        List<AggregationOperation> operations = new ArrayList<>();
        if (userId != null) {
            operations.add(Aggregation.match(Criteria.where("userId").is(userId)));
        }
        operations.add(context -> new Document("$facet", new Document()
                .append("summary", summaryPipeline())
                .append("comparisonGroups", comparisonPipeline())
                .append("daily", dailyPipeline(firstDay))));

        Document result = mongoTemplate.aggregate(
                        Aggregation.newAggregation(operations),
                        COLLECTION,
                        Document.class
                )
                .getUniqueMappedResult();
        if (result == null) {
            return DashboardStatisticsSnapshot.empty();
        }

        Document summary = firstDocument(result, "summary");
        Document comparisons = firstDocument(result, "comparisonGroups");
        return new DashboardStatisticsSnapshot(
                number(summary, "totalInference").longValue(),
                number(summary, "singleAnalysis").longValue(),
                number(comparisons, "count").longValue(),
                number(summary, "detected").longValue(),
                number(summary, "notDetected").longValue(),
                number(summary, "baselineUsage").longValue(),
                number(summary, "vmambaUsage").longValue(),
                number(summary, "totalMasks").longValue(),
                number(summary, "activityLast24Hours").longValue(),
                number(summary, "averageProcessingTimeMs").doubleValue(),
                number(summary, "averageDetectedConfidence").doubleValue(),
                dailyUsage(result)
        );
    }

    private List<Document> summaryPipeline() {
        Object comparison = new Document("$eq", List.of("$comparisonResult", true));
        Object detected = new Document("$eq", List.of("$detected", true));
        Object recent = new Document(
                "$gte",
                List.of(
                        "$createdAt",
                        java.util.Date.from(
                                java.time.Instant.now().minus(java.time.Duration.ofHours(24))
                        )
                )
        );
        Object validProcessingTime = new Document("$and", List.of(
                new Document("$ne", Arrays.asList("$processingTimeMs", null)),
                new Document("$gte", List.of("$processingTimeMs", 0))
        ));
        Object validDetectedConfidence = new Document("$and", List.of(
                detected,
                new Document("$ne", Arrays.asList("$confidence", null)),
                new Document("$gte", List.of("$confidence", 0))
        ));

        Document group = new Document("_id", null)
                .append("totalInference", new Document("$sum", 1))
                .append("singleAnalysis", sumWhen(new Document("$not", List.of(comparison))))
                .append("detected", sumWhen(detected))
                .append("notDetected", sumWhen(new Document("$not", List.of(detected))))
                .append("baselineUsage", sumWhen(new Document("$eq", List.of("$modelType", BASELINE_MODEL))))
                .append("vmambaUsage", sumWhen(new Document("$eq", List.of("$modelType", VMAMBA_MODEL))))
                .append("totalMasks", new Document(
                        "$sum",
                        new Document("$ifNull", List.of("$maskCount", 0))
                ))
                .append("activityLast24Hours", sumWhen(recent))
                .append("averageProcessingTimeMs", new Document(
                        "$avg",
                        new Document(
                                "$cond",
                                Arrays.asList(validProcessingTime, "$processingTimeMs", null)
                        )
                ))
                .append("averageDetectedConfidence", new Document(
                        "$avg",
                        new Document(
                                "$cond",
                                Arrays.asList(validDetectedConfidence, "$confidence", null)
                        )
                ));
        return List.of(new Document("$group", group));
    }

    private List<Document> comparisonPipeline() {
        return List.of(
                new Document("$match", new Document("comparisonResult", true)
                        .append("comparisonGroupId", new Document("$type", "string").append("$ne", ""))
                        .append("modelType", new Document(
                                "$in",
                                List.of(BASELINE_MODEL, VMAMBA_MODEL)
                        ))),
                new Document("$group", new Document("_id", "$comparisonGroupId")
                        .append("models", new Document("$addToSet", "$modelType"))),
                new Document("$match", new Document(
                        "$expr",
                        new Document(
                                "$eq",
                                List.of(new Document("$size", "$models"), 2)
                        )
                )),
                new Document("$count", "count")
        );
    }

    private List<Document> dailyPipeline(LocalDate firstDay) {
        java.util.Date firstMoment = java.util.Date.from(
                firstDay.atStartOfDay(DASHBOARD_ZONE).toInstant()
        );
        Document dateKey = new Document("format", "%Y-%m-%d")
                .append("date", "$createdAt")
                .append("timezone", DASHBOARD_ZONE.getId());
        return List.of(
                new Document("$match", new Document(
                        "createdAt",
                        new Document("$gte", firstMoment)
                )),
                new Document("$group", new Document(
                        "_id",
                        new Document("$dateToString", dateKey)
                ).append("count", new Document("$sum", 1))),
                new Document("$sort", new Document("_id", 1))
        );
    }

    private Document sumWhen(Object condition) {
        return new Document("$sum", new Document("$cond", List.of(condition, 1, 0)));
    }

    private Document firstDocument(Document result, String key) {
        List<Document> documents = documents(result, key);
        return documents.isEmpty() ? new Document() : documents.get(0);
    }

    @SuppressWarnings("unchecked")
    private List<Document> documents(Document result, String key) {
        Object value = result.get(key);
        return value instanceof List<?> list
                ? (List<Document>) list
                : List.of();
    }

    private Map<LocalDate, Long> dailyUsage(Document result) {
        Map<LocalDate, Long> usage = new LinkedHashMap<>();
        for (Document item : documents(result, "daily")) {
            Object date = item.get("_id");
            if (date instanceof String dateValue) {
                usage.put(LocalDate.parse(dateValue), number(item, "count").longValue());
            }
        }
        return usage;
    }

    private Number number(Document document, String key) {
        Object value = document.get(key);
        return value instanceof Number number ? number : 0;
    }
}
