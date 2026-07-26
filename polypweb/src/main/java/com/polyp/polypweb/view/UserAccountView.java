package com.polyp.polypweb.view;

import com.polyp.polypweb.document.UserRole;

import java.time.LocalDateTime;

public class UserAccountView {

    private final String id;
    private final String fullName;
    private final String email;
    private final UserRole role;
    private final boolean enabled;
    private final LocalDateTime createdAt;

    public UserAccountView(
            String id,
            String fullName,
            String email,
            UserRole role,
            boolean enabled,
            LocalDateTime createdAt) {
        this.id = id;
        this.fullName = fullName;
        this.email = email;
        this.role = role;
        this.enabled = enabled;
        this.createdAt = createdAt;
    }

    public String getId() {
        return id;
    }

    public String getFullName() {
        return fullName;
    }

    public String getEmail() {
        return email;
    }

    public UserRole getRole() {
        return role;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }
}
