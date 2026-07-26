package com.polyp.polypweb.repository;

import com.polyp.polypweb.view.filter.ComparisonHistoryFilter;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.aggregation.Aggregation;
import org.springframework.data.mongodb.core.aggregation.AggregationResults;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class ComparisonHistorySearchRepositoryTests {

    @Mock
    private MongoTemplate mongoTemplate;

    private ComparisonHistorySearchRepository repository;

    @BeforeEach
    void setUp() {
        repository = new ComparisonHistorySearchRepository(mongoTemplate);
    }

    @Test
    void aggregationGroupsBeforePaginationAndCountsGroupsNotDocuments() {
        Document response = new Document("invalidGroups", List.of())
                .append(
                        "records",
                        List.of(new Document()
                                .append("metadata", List.of(new Document("count", 27)))
                                .append("data", List.of()))
                );
        when(mongoTemplate.aggregate(
                any(Aggregation.class),
                eq("diagnosis_history"),
                eq(Document.class)
        )).thenReturn(new AggregationResults<>(List.of(response), new Document()));
        ComparisonHistoryFilter filter = new ComparisonHistoryFilter();
        filter.setPage("1");
        filter.setSize("10");
        filter.normalize();

        Page<ComparisonHistoryRecord> page = repository.search("user-a", filter);

        ArgumentCaptor<Aggregation> captor = ArgumentCaptor.forClass(Aggregation.class);
        verify(mongoTemplate).aggregate(
                captor.capture(),
                eq("diagnosis_history"),
                eq(Document.class)
        );
        List<Document> pipeline = captor.getValue().toPipeline(Aggregation.DEFAULT_CONTEXT);
        String rendered = pipeline.toString();
        assertTrue(rendered.indexOf("$group") < rendered.indexOf("$facet"));
        assertTrue(rendered.contains("baselineCount"));
        assertTrue(rendered.contains("vmambaCount"));
        assertTrue(rendered.contains("originalImageUrls"));
        assertTrue(rendered.contains("fileNames"));
        assertTrue(rendered.contains("$skip=10") || rendered.contains("$skip: 10"));
        assertEquals(27, page.getTotalElements());
        assertEquals(1, page.getNumber());
    }

    @Test
    void aggregationMatchesCurrentUserAndAppliesPostGroupFilters() {
        Document response = new Document("invalidGroups", List.of())
                .append(
                        "records",
                        List.of(new Document()
                                .append("metadata", List.of())
                                .append("data", List.of()))
                );
        when(mongoTemplate.aggregate(
                any(Aggregation.class),
                eq("diagnosis_history"),
                eq(Document.class)
        )).thenReturn(new AggregationResults<>(List.of(response), new Document()));
        ComparisonHistoryFilter filter = new ComparisonHistoryFilter();
        filter.setKeyword("case.*");
        filter.setBaselineDetected("true");
        filter.setVmambaDetected("false");
        filter.setDateFrom("2026-07-01");
        filter.setDateTo("2026-07-31");
        filter.setSort("total-processing-desc");
        filter.normalize();

        repository.search("user-a", filter);

        ArgumentCaptor<Aggregation> captor = ArgumentCaptor.forClass(Aggregation.class);
        verify(mongoTemplate).aggregate(
                captor.capture(),
                eq("diagnosis_history"),
                eq(Document.class)
        );
        String rendered = captor.getValue()
                .toPipeline(Aggregation.DEFAULT_CONTEXT)
                .toString();
        assertTrue(rendered.contains("user-a"));
        assertTrue(rendered.contains("\\Qcase.*\\E"));
        assertTrue(rendered.contains("baseline.detected"));
        assertTrue(rendered.contains("vmamba.detected"));
        assertTrue(rendered.contains("totalProcessingTimeMs"));
    }
}
