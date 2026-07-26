package com.polyp.polypweb.view;

import org.springframework.data.domain.Page;

import java.util.List;
import java.util.stream.IntStream;

public class PageNavigationView {

    private final int currentPage;
    private final int totalPages;
    private final long totalItems;
    private final long firstItem;
    private final long lastItem;
    private final List<Integer> pageNumbers;

    private PageNavigationView(
            int currentPage,
            int totalPages,
            long totalItems,
            long firstItem,
            long lastItem,
            List<Integer> pageNumbers) {
        this.currentPage = currentPage;
        this.totalPages = totalPages;
        this.totalItems = totalItems;
        this.firstItem = firstItem;
        this.lastItem = lastItem;
        this.pageNumbers = List.copyOf(pageNumbers);
    }

    public static PageNavigationView from(Page<?> page) {
        int startPage = Math.max(0, page.getNumber() - 2);
        int endPage = Math.min(page.getTotalPages() - 1, page.getNumber() + 2);
        List<Integer> numbers = endPage < startPage
                ? List.of()
                : IntStream.rangeClosed(startPage, endPage).boxed().toList();
        long first = page.isEmpty() ? 0 : (long) page.getNumber() * page.getSize() + 1;
        long last = page.isEmpty() ? 0 : first + page.getNumberOfElements() - 1;
        return new PageNavigationView(
                page.getNumber(),
                page.getTotalPages(),
                page.getTotalElements(),
                first,
                last,
                numbers
        );
    }

    public int getCurrentPage() {
        return currentPage;
    }

    public int getDisplayPage() {
        return totalPages == 0 ? 0 : currentPage + 1;
    }

    public int getTotalPages() {
        return totalPages;
    }

    public long getTotalItems() {
        return totalItems;
    }

    public long getFirstItem() {
        return firstItem;
    }

    public long getLastItem() {
        return lastItem;
    }

    public List<Integer> getPageNumbers() {
        return pageNumbers;
    }

    public boolean isFirst() {
        return currentPage <= 0;
    }

    public boolean isLast() {
        return totalPages == 0 || currentPage >= totalPages - 1;
    }

    public int getPreviousPage() {
        return Math.max(0, currentPage - 1);
    }

    public int getNextPage() {
        return Math.min(Math.max(0, totalPages - 1), currentPage + 1);
    }

    public int getLastPage() {
        return Math.max(0, totalPages - 1);
    }
}
