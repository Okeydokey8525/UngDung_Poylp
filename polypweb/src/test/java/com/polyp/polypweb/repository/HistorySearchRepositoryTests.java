package com.polyp.polypweb.repository;

import com.polyp.polypweb.document.DiagnosisHistory;
import com.polyp.polypweb.view.filter.HistoryFilter;
import org.bson.Document;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Query;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class HistorySearchRepositoryTests {

    @Mock
    private MongoTemplate mongoTemplate;

    private HistorySearchRepository repository;

    @BeforeEach
    void setUp() {
        repository = new HistorySearchRepository(mongoTemplate);
        when(mongoTemplate.count(any(Query.class), eq(DiagnosisHistory.class)))
                .thenReturn(25L);
        when(mongoTemplate.find(any(Query.class), eq(DiagnosisHistory.class)))
                .thenReturn(List.of(new DiagnosisHistory()));
    }

    @Test
    void queryScopesUserExcludesComparisonAndAppliesDatabasePagination() {
        HistoryFilter filter = new HistoryFilter();
        filter.setPage("1");
        filter.setSize("10");
        filter.normalize();

        Page<DiagnosisHistory> page = repository.search("user-a", filter);

        ArgumentCaptor<Query> captor = ArgumentCaptor.forClass(Query.class);
        verify(mongoTemplate).find(captor.capture(), eq(DiagnosisHistory.class));
        Query query = captor.getValue();
        String criteria = query.getQueryObject().toJson();
        assertTrue(criteria.contains("\"userId\": \"user-a\""));
        assertTrue(criteria.contains("\"comparisonResult\": false"));
        assertTrue(criteria.contains("\"comparisonResult\": null"));
        assertEquals(10, query.getSkip());
        assertEquals(10, query.getLimit());
        assertEquals(25, page.getTotalElements());
        assertEquals(1, page.getNumber());
    }

    @Test
    void keywordIsRegexEscapedAndModelDetectionDateFiltersRemainServerSide() {
        HistoryFilter filter = new HistoryFilter();
        filter.setKeyword("case.*(test)");
        filter.setModel("YOLO26s-TSVM-FP32-seg");
        filter.setDetected("true");
        filter.setDateFrom("2026-07-01");
        filter.setDateTo("2026-07-31");
        filter.normalize();

        repository.search("user-a", filter);

        ArgumentCaptor<Query> captor = ArgumentCaptor.forClass(Query.class);
        verify(mongoTemplate).find(captor.capture(), eq(DiagnosisHistory.class));
        Document query = captor.getValue().getQueryObject();
        String rendered = query.toString();
        assertTrue(rendered.contains("\\Qcase.*(test)\\E"));
        assertTrue(rendered.contains("YOLO26s-TSVM-FP32-seg"));
        assertTrue(rendered.contains("detected=true"));
        assertTrue(rendered.contains("createdAt"));
    }

    @Test
    void sortUsesOnlyWhitelistedFieldAndStableIdTieBreaker() {
        HistoryFilter filter = new HistoryFilter();
        filter.setSort("confidence-desc");
        filter.normalize();

        repository.search("user-a", filter);

        ArgumentCaptor<Query> captor = ArgumentCaptor.forClass(Query.class);
        verify(mongoTemplate).find(captor.capture(), eq(DiagnosisHistory.class));
        Document sort = captor.getValue().getSortObject();
        assertEquals(-1, sort.get("confidence"));
        assertEquals(-1, sort.get("_id"));
        assertFalse(sort.containsKey("userId"));
    }
}
