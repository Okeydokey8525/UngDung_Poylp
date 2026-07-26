package com.polyp.polypweb.security;

import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

import java.io.Serial;
import java.util.Collection;
import java.util.List;

public class CurrentUserPrincipal implements UserDetails {

    @Serial
    private static final long serialVersionUID = 1L;

    private final String userId;
    private final String email;
    private final String fullName;
    private final UserRole role;
    private final String passwordHash;
    private final boolean enabled;

    public CurrentUserPrincipal(UserAccount account) {
        this.userId = account.getId();
        this.email = account.getEmail();
        this.fullName = account.getFullName();
        this.role = account.getRole();
        this.passwordHash = account.getPasswordHash();
        this.enabled = account.isEnabled();
    }

    public String getUserId() {
        return userId;
    }

    public String getEmail() {
        return email;
    }

    public String getFullName() {
        return fullName;
    }

    public UserRole getRole() {
        return role;
    }

    public boolean isAdmin() {
        return role == UserRole.ADMIN;
    }

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + role.name()));
    }

    @Override
    public String getPassword() {
        return passwordHash;
    }

    @Override
    public String getUsername() {
        return email;
    }

    @Override
    public boolean isAccountNonExpired() {
        return true;
    }

    @Override
    public boolean isAccountNonLocked() {
        return true;
    }

    @Override
    public boolean isCredentialsNonExpired() {
        return true;
    }

    @Override
    public boolean isEnabled() {
        return enabled;
    }
}
