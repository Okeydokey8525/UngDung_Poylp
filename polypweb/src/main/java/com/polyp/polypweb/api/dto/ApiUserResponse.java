package com.polyp.polypweb.api.dto;

import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;

import java.time.LocalDateTime;

public record ApiUserResponse(
        String id,
        String fullName,
        String email,
        UserRole role,
        LocalDateTime createdAt,
        LocalDateTime updatedAt
) {
    public static ApiUserResponse from(UserAccount account) {
        return new ApiUserResponse(
                account.getId(),
                account.getFullName(),
                account.getEmail(),
                account.getRole(),
                account.getCreatedAt(),
                account.getUpdatedAt()
        );
    }
}
