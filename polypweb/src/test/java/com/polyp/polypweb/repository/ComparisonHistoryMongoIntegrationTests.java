package com.polyp.polypweb.repository;

import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.polyp.polypweb.service.ModelComparisonService;
import com.polyp.polypweb.view.filter.ComparisonHistoryFilter;
import org.bson.Document;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.data.domain.Page;
import org.springframework.data.mongodb.core.MongoTemplate;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Opt-in server-backed checks: set COMPARISON_TEST_MONGODB_URI to an isolated MongoDB.
 * Every test creates and drops only its own randomly named test database.
 */
@EnabledIfEnvironmentVariable(named = "COMPARISON_TEST_MONGODB_URI", matches = ".+")
class ComparisonHistoryMongoIntegrationTests {

    private static final ZoneId APPLICATION_ZONE = ZoneId.of("Asia/Ho_Chi_Minh");
    private static MongoClient client;
    private MongoTemplate mongoTemplate;
    private ComparisonHistorySearchRepository repository;

    @BeforeAll
    static void connect() {
        client = MongoClients.create(System.getenv("COMPARISON_TEST_MONGODB_URI"));
    }

    @BeforeEach
    void createPrivateDatabase() {
        String databaseName = "polypweb_comparison_it_" + UUID.randomUUID().toString().replace("-", "");
        mongoTemplate = new MongoTemplate(client, databaseName);
        repository = new ComparisonHistorySearchRepository(mongoTemplate);
    }

    @AfterEach
    void dropPrivateDatabase() {
        if (mongoTemplate != null) {
            mongoTemplate.getDb().drop();
        }
    }

    @AfterAll
    static void disconnect() {
        if (client != null) {
            client.close();
        }
    }

    @Test
    void emptyCollectionReturnsAnEmptyPageWithoutAnIllegalNestedFacet() {
        Page<ComparisonHistoryRecord> page = repository.search("user-a", filter());

        assertTrue(page.isEmpty());
        assertEquals(0, page.getTotalElements());
    }

    @Test
    void countsAndPagesOnlyCompleteConsistentPairsOwnedByTheCurrentUser() {
        List<Document> documents = new ArrayList<>();
        LocalDateTime start = LocalDateTime.of(2026, 7, 1, 12, 0);
        for (int i = 0; i < 25; i++) {
            documents.addAll(pair("user-a", "g%02d".formatted(i), "case-%02d.jpg".formatted(i),
                    start.plusDays(i), true, false, 10, 20));
        }
        // Reusing a group id under another owner must not invalidate user-a's pair.
        documents.addAll(pair("user-b", "g24", "other-owner.jpg", start.plusDays(40), true, true, 10, 20));
        documents.add(document("user-a", "incomplete", "one.jpg", ModelComparisonService.BASELINE_MODEL,
                start, true, 10, "/original/incomplete"));
        documents.addAll(pair("user-a", "duplicate", "dup.jpg", start, true, true, 10, 20));
        documents.add(document("user-a", "duplicate", "dup.jpg", ModelComparisonService.BASELINE_MODEL,
                start, true, 10, "/original/duplicate"));
        documents.add(document("user-a", "bad-file", "a.jpg", ModelComparisonService.BASELINE_MODEL,
                start, true, 10, "/original/bad-file"));
        documents.add(document("user-a", "bad-file", "b.jpg", ModelComparisonService.VMAMBA_MODEL,
                start, false, 20, "/original/bad-file"));
        documents.add(document("user-a", "bad-url", "url.jpg", ModelComparisonService.BASELINE_MODEL,
                start, true, 10, "/original/a"));
        documents.add(document("user-a", "bad-url", "url.jpg", ModelComparisonService.VMAMBA_MODEL,
                start, false, 20, "/original/b"));
        insert(documents);
        ComparisonHistoryFilter filter = filter();
        filter.setPage("1");
        filter.normalize();

        Page<ComparisonHistoryRecord> page = repository.search("user-a", filter);

        assertEquals(25, page.getTotalElements());
        assertEquals(10, page.getNumberOfElements());
        assertEquals("g14", page.getContent().get(0).comparisonGroupId());
        assertTrue(page.stream().allMatch(record -> "user-a".equals(record.baseline().getUserId())
                && "user-a".equals(record.vmamba().getUserId())));
        assertEquals(1, repository.search("user-b", filter()).getTotalElements());
    }

    @Test
    void literalKeywordDetectionAndLocalDateFiltersApplyBeforeBothCountAndPaging() {
        List<Document> documents = new ArrayList<>();
        LocalDateTime july = LocalDateTime.of(2026, 7, 1, 0, 0);
        documents.addAll(pair("user-a", "match", "case.*special.jpg", july, true, false, 10, 20));
        documents.addAll(pair("user-a", "not-literal", "caseZZspecial.jpg", july, true, false, 10, 20));
        documents.addAll(pair("user-a", "too-early", "case.*early.jpg", july.minusMinutes(1), true, false, 10, 20));
        documents.addAll(pair("user-a", "too-late", "case.*late.jpg", july.plusMonths(1), true, false, 10, 20));
        documents.addAll(pair("user-a", "wrong-detection", "case.*both.jpg", july, true, true, 10, 20));
        documents.addAll(pair("user-b", "other-owner", "case.*other.jpg", july, true, false, 10, 20));
        insert(documents);
        ComparisonHistoryFilter filter = filter();
        filter.setKeyword("case.*");
        filter.setBaselineDetected("true");
        filter.setVmambaDetected("false");
        filter.setDateFrom("2026-07-01");
        filter.setDateTo("2026-07-31");
        filter.normalize();

        Page<ComparisonHistoryRecord> page = repository.search("user-a", filter);

        assertEquals(1, page.getTotalElements());
        assertEquals("match", page.getContent().get(0).comparisonGroupId());
        assertEquals(july, page.getContent().get(0).createdAt());
    }

    @Test
    void computedSortHasAStableTieBreakerAndOutOfRangePagesRetainTheFilteredTotal() {
        LocalDateTime time = LocalDateTime.of(2026, 7, 1, 12, 0);
        List<Document> documents = new ArrayList<>();
        documents.addAll(pair("user-a", "b", "b.jpg", time, true, true, 7, 13));
        documents.addAll(pair("user-a", "a", "a.jpg", time, true, true, 5, 15));
        documents.addAll(pair("user-a", "c", "c.jpg", time, true, true, 3, 7));
        insert(documents);
        ComparisonHistoryFilter filter = filter();
        filter.setSort("total-processing-desc");
        filter.normalize();

        Page<ComparisonHistoryRecord> first = repository.search("user-a", filter);

        assertEquals(List.of("a", "b", "c"), first.stream().map(ComparisonHistoryRecord::comparisonGroupId).toList());
        assertEquals(20, first.getContent().get(0).totalProcessingTimeMs());
        filter.setPage("2");
        filter.normalize();
        Page<ComparisonHistoryRecord> outside = repository.search("user-a", filter);
        assertTrue(outside.isEmpty());
        assertEquals(3, outside.getTotalElements());
    }

    private ComparisonHistoryFilter filter() {
        return new ComparisonHistoryFilter().normalize();
    }

    private void insert(List<Document> documents) {
        mongoTemplate.getCollection("diagnosis_history").insertMany(documents);
    }

    private List<Document> pair(String user, String group, String file, LocalDateTime time,
                                boolean baselineDetected, boolean vmambaDetected, double baselineMs, double vmambaMs) {
        return List.of(
                document(user, group, file, ModelComparisonService.BASELINE_MODEL, time, baselineDetected, baselineMs, "/original/" + group),
                document(user, group, file, ModelComparisonService.VMAMBA_MODEL, time, vmambaDetected, vmambaMs, "/original/" + group)
        );
    }

    private Document document(String user, String group, String file, String model, LocalDateTime time,
                              boolean detected, double processingMs, String originalUrl) {
        return new Document("userId", user).append("comparisonGroupId", group)
                .append("comparisonResult", true).append("fileName", file).append("modelType", model)
                .append("detected", detected).append("label", detected ? "polyp" : null)
                .append("confidence", detected ? 0.8 : 0.0).append("maskCount", detected ? 1 : 0)
                .append("processingTimeMs", processingMs).append("originalImageUrl", originalUrl)
                .append("resultImageUrl", "/result/" + group + "/" + model)
                .append("createdAt", Date.from(time.atZone(APPLICATION_ZONE).toInstant()));
    }
}
