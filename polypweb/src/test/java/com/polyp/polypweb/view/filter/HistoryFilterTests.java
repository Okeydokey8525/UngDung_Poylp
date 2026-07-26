package com.polyp.polypweb.view.filter;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class HistoryFilterTests {

    @Test
    void historyDefaultsAreSafe() {
        HistoryFilter filter = new HistoryFilter().normalize();

        assertEquals(0, filter.getPageIndex());
        assertEquals(10, filter.getPageSize());
        assertEquals(ModelFilterOption.ALL, filter.getModelOption());
        assertEquals(DetectionFilterOption.ALL, filter.getDetectionOption());
        assertEquals(HistorySortOption.NEWEST, filter.getSortOption());
        assertTrue(filter.getValidationMessages().isEmpty());
    }

    @Test
    void negativePageAndUnsupportedSizeAreNormalized() {
        HistoryFilter filter = new HistoryFilter();
        filter.setPage("-5");
        filter.setSize("999");
        filter.normalize();

        assertEquals(0, filter.getPageIndex());
        assertEquals(10, filter.getPageSize());
    }

    @Test
    void invalidWhitelistedValuesDoNotReachMongoFieldSelection() {
        HistoryFilter filter = new HistoryFilter();
        filter.setModel("$where");
        filter.setDetected("maybe");
        filter.setSort("userId");
        filter.normalize();

        assertEquals(ModelFilterOption.ALL, filter.getModelOption());
        assertEquals(DetectionFilterOption.ALL, filter.getDetectionOption());
        assertEquals(HistorySortOption.NEWEST, filter.getSortOption());
        assertEquals(3, filter.getValidationMessages().size());
    }

    @Test
    void keywordIsTrimmedAndLimitedToOneHundredCharacters() {
        HistoryFilter filter = new HistoryFilter();
        filter.setKeyword("  " + "a".repeat(120) + "  ");
        filter.normalize();

        assertEquals(100, filter.getKeyword().length());
        assertFalse(filter.getValidationMessages().isEmpty());
    }

    @Test
    void malformedDateProducesMessageWithoutException() {
        HistoryFilter filter = new HistoryFilter();
        filter.setDateFrom("2026-99-99");
        filter.normalize();

        assertNull(filter.getParsedDateFrom());
        assertFalse(filter.getValidationMessages().isEmpty());
    }

    @Test
    void reversedDateRangeIsRejectedWithoutApplyingPartialRange() {
        HistoryFilter filter = new HistoryFilter();
        filter.setDateFrom("2026-07-31");
        filter.setDateTo("2026-07-01");
        filter.normalize();

        assertNull(filter.getParsedDateFrom());
        assertNull(filter.getParsedDateTo());
        assertTrue(filter.getValidationMessages().stream()
                .anyMatch(message -> message.contains("không được sau")));
    }

    @Test
    void comparisonFilterAcceptsOnlySupportedStatusAndSort() {
        ComparisonHistoryFilter filter = new ComparisonHistoryFilter();
        filter.setBaselineDetected("detected");
        filter.setVmambaDetected("not-detected");
        filter.setSort("total-processing-asc");
        filter.setSize("20");
        filter.normalize();

        assertEquals(DetectionFilterOption.DETECTED, filter.getBaselineDetectionOption());
        assertEquals(DetectionFilterOption.NOT_DETECTED, filter.getVmambaDetectionOption());
        assertEquals(ComparisonSortOption.TOTAL_PROCESSING_ASC, filter.getSortOption());
        assertEquals(20, filter.getPageSize());
    }

    @Test
    void comparisonInvalidInputFallsBackSafely() {
        ComparisonHistoryFilter filter = new ComparisonHistoryFilter();
        filter.setPage("not-a-number");
        filter.setSize("1");
        filter.setBaselineDetected("unknown");
        filter.setVmambaDetected("unknown");
        filter.setSort("$function");
        filter.normalize();

        assertEquals(0, filter.getPageIndex());
        assertEquals(10, filter.getPageSize());
        assertEquals(DetectionFilterOption.ALL, filter.getBaselineDetectionOption());
        assertEquals(DetectionFilterOption.ALL, filter.getVmambaDetectionOption());
        assertEquals(ComparisonSortOption.NEWEST, filter.getSortOption());
        assertEquals(3, filter.getValidationMessages().size());
    }
}
