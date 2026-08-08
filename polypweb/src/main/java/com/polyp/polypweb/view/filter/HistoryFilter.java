package com.polyp.polypweb.view.filter;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

public class HistoryFilter {

    private static final int DEFAULT_PAGE_SIZE = 10;
    private static final int MAX_KEYWORD_LENGTH = 100;
    private static final Set<Integer> ALLOWED_PAGE_SIZES = Set.of(10, 20, 50);

    private String keyword = "";
    private String model = "ALL";
    private String detected = "ALL";
    private String dateFrom = "";
    private String dateTo = "";
    private String sort = "newest";
    private String page = "0";
    private String size = Integer.toString(DEFAULT_PAGE_SIZE);

    private int pageIndex;
    private int pageSize = DEFAULT_PAGE_SIZE;
    private ModelFilterOption modelOption = ModelFilterOption.ALL;
    private DetectionFilterOption detectionOption = DetectionFilterOption.ALL;
    private HistorySortOption sortOption = HistorySortOption.NEWEST;
    private LocalDate parsedDateFrom;
    private LocalDate parsedDateTo;
    private boolean invalidDateFormat;
    private boolean invalidDateRange;
    private final List<String> validationMessages = new ArrayList<>();

    public HistoryFilter normalize() {
        validationMessages.clear();
        invalidDateFormat = false;
        invalidDateRange = false;
        keyword = keyword == null ? "" : keyword.trim();
        if (keyword.length() > MAX_KEYWORD_LENGTH) {
            keyword = keyword.substring(0, MAX_KEYWORD_LENGTH);
            validationMessages.add("Từ khóa đã được giới hạn còn 100 ký tự.");
        }

        pageIndex = parseNonNegative(page, 0);
        pageSize = parsePageSize(size);

        modelOption = ModelFilterOption.parse(model).orElseGet(() -> {
            validationMessages.add("Mô hình lọc không hợp lệ; đã chuyển về Tất cả.");
            return ModelFilterOption.ALL;
        });
        model = modelOption.getQueryValue();

        detectionOption = DetectionFilterOption.parse(detected).orElseGet(() -> {
            validationMessages.add("Trạng thái phát hiện không hợp lệ; đã chuyển về Tất cả.");
            return DetectionFilterOption.ALL;
        });
        detected = detectionOption.getQueryValue();

        sortOption = HistorySortOption.parse(sort).orElseGet(() -> {
            validationMessages.add("Kiểu sắp xếp không hợp lệ; đã chuyển về Mới nhất.");
            return HistorySortOption.NEWEST;
        });
        sort = sortOption.getQueryValue();

        parsedDateFrom = parseDate(dateFrom, "Ngày bắt đầu");
        parsedDateTo = parseDate(dateTo, "Ngày kết thúc");
        if (parsedDateFrom != null
                && parsedDateTo != null
                && parsedDateFrom.isAfter(parsedDateTo)) {
            validationMessages.add("Ngày bắt đầu không được sau ngày kết thúc.");
            invalidDateRange = true;
            parsedDateFrom = null;
            parsedDateTo = null;
        }
        return this;
    }

    private int parseNonNegative(String value, int fallback) {
        try {
            return Math.max(0, Integer.parseInt(value));
        } catch (NumberFormatException exception) {
            return fallback;
        }
    }

    private int parsePageSize(String value) {
        try {
            int parsed = Integer.parseInt(value);
            return ALLOWED_PAGE_SIZES.contains(parsed) ? parsed : DEFAULT_PAGE_SIZE;
        } catch (NumberFormatException exception) {
            return DEFAULT_PAGE_SIZE;
        }
    }

    private LocalDate parseDate(String value, String label) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return LocalDate.parse(value.trim());
        } catch (DateTimeParseException exception) {
            invalidDateFormat = true;
            validationMessages.add(label + " phải có định dạng yyyy-MM-dd.");
            return null;
        }
    }

    public String getKeyword() {
        return keyword;
    }

    public void setKeyword(String keyword) {
        this.keyword = keyword;
    }

    public String getModel() {
        return model;
    }

    public void setModel(String model) {
        this.model = model;
    }

    public String getDetected() {
        return detected;
    }

    public void setDetected(String detected) {
        this.detected = detected;
    }

    public String getDateFrom() {
        return dateFrom;
    }

    public void setDateFrom(String dateFrom) {
        this.dateFrom = dateFrom == null ? "" : dateFrom;
    }

    public String getDateTo() {
        return dateTo;
    }

    public void setDateTo(String dateTo) {
        this.dateTo = dateTo == null ? "" : dateTo;
    }

    public String getSort() {
        return sort;
    }

    public void setSort(String sort) {
        this.sort = sort;
    }

    public void setPage(String page) {
        this.page = page;
    }

    public void setSize(String size) {
        this.size = size;
    }

    public int getPageIndex() {
        return pageIndex;
    }

    public int getPageSize() {
        return pageSize;
    }

    public ModelFilterOption getModelOption() {
        return modelOption;
    }

    public DetectionFilterOption getDetectionOption() {
        return detectionOption;
    }

    public HistorySortOption getSortOption() {
        return sortOption;
    }

    public LocalDate getParsedDateFrom() {
        return parsedDateFrom;
    }

    public LocalDate getParsedDateTo() {
        return parsedDateTo;
    }

    public List<String> getValidationMessages() {
        return List.copyOf(validationMessages);
    }

    public boolean hasInvalidDateFormat() {
        return invalidDateFormat;
    }

    public boolean hasInvalidDateRange() {
        return invalidDateRange;
    }
}
