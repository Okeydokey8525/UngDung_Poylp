package com.polyp.polypweb.api.dto;

import org.springframework.data.domain.Page;

import java.util.List;

public record ApiPagedResponse<T>(
        List<T> items,
        int page,
        int size,
        long totalItems,
        int totalPages,
        boolean hasNext,
        boolean hasPrevious
) {

    public static <T> ApiPagedResponse<T> from(Page<T> page) {
        return new ApiPagedResponse<>(
                List.copyOf(page.getContent()),
                page.getNumber(),
                page.getSize(),
                page.getTotalElements(),
                page.getTotalPages(),
                page.hasNext(),
                page.hasPrevious()
        );
    }
}
