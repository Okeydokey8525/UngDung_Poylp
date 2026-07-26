package com.polyp.polypweb.repository;

import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.aggregation.Aggregation;
import org.springframework.data.mongodb.core.aggregation.AggregationResults;

import java.time.LocalDate;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class DashboardStatisticsRepositoryTests {

    @Mock
    private MongoTemplate mongoTemplate;

    private DashboardStatisticsRepository repository;

    @BeforeEach
    void setUp() {
        repository = new DashboardStatisticsRepository(mongoTemplate);
    }

    @Test
    void emptyAggregationResultReturnsSafeZeroSnapshot() {
        when(mongoTemplate.aggregate(
                any(Aggregation.class),
                eq("diagnosis_history"),
                eq(Document.class)
        )).thenReturn(new AggregationResults<>(List.of(), new Document()));

        DashboardStatisticsSnapshot snapshot = repository.aggregate("user-a", 7);

        assertEquals(0, snapshot.getTotalInference());
        assertEquals(0, snapshot.getTotalMasks());
        assertEquals(0, snapshot.getAverageDetectedConfidence());
        assertTrue(snapshot.getDailyUsage().isEmpty());
    }

    @Test
    void legacyDocumentWithoutMaskCountIsMappedAsZero() {
        Document result = new Document(
                "summary",
                List.of(new Document("totalInference", 1)
                        .append("singleAnalysis", 1)
                        .append("detected", 1)
                        .append("notDetected", 0)
                        .append("averageDetectedConfidence", 82.5))
        ).append("comparisonGroups", List.of())
                .append(
                        "daily",
                        List.of(new Document("_id", "2026-07-26").append("count", 1))
                );
        when(mongoTemplate.aggregate(
                any(Aggregation.class),
                eq("diagnosis_history"),
                eq(Document.class)
        )).thenReturn(new AggregationResults<>(List.of(result), new Document()));

        DashboardStatisticsSnapshot snapshot = repository.aggregate("user-a", 7);

        assertEquals(1, snapshot.getTotalInference());
        assertEquals(0, snapshot.getTotalMasks());
        assertEquals(82.5, snapshot.getAverageDetectedConfidence());
        assertEquals(1, snapshot.getDailyUsage().get(LocalDate.of(2026, 7, 26)));
    }

    @Test
    @SuppressWarnings("unchecked")
    void userAggregationIsScopedAndUsesFacetNullFallbackAndDistinctModels() {
        when(mongoTemplate.aggregate(
                any(Aggregation.class),
                eq("diagnosis_history"),
                eq(Document.class)
        )).thenReturn(new AggregationResults<>(List.of(), new Document()));

        repository.aggregate("user-a", 7);

        ArgumentCaptor<Aggregation> captor = ArgumentCaptor.forClass(Aggregation.class);
        verify(mongoTemplate).aggregate(
                captor.capture(),
                eq("diagnosis_history"),
                eq(Document.class)
        );
        List<Document> pipeline = captor.getValue().toPipeline(Aggregation.DEFAULT_CONTEXT);
        Document userMatch = (Document) pipeline.get(0).get("$match");
        assertEquals("user-a", userMatch.getString("userId"));

        Document facet = (Document) pipeline.get(1).get("$facet");
        List<Document> summary = (List<Document>) facet.get("summary");
        List<Document> comparisonGroups = (List<Document>) facet.get("comparisonGroups");
        assertTrue(summary.toString().contains("$ifNull"));
        assertTrue(comparisonGroups.toString().contains("$addToSet"));
        assertTrue(comparisonGroups.toString().contains("comparisonGroupId"));
    }
}
