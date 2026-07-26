package com.polyp.polypweb.repository;

import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import org.springframework.data.mongodb.repository.MongoRepository;

import java.util.List;
import java.util.Optional;

public interface UserAccountRepository extends MongoRepository<UserAccount, String> {

    Optional<UserAccount> findByEmailIgnoreCase(String email);

    boolean existsByEmailIgnoreCase(String email);

    long countByRole(UserRole role);

    long countByRoleAndEnabledTrue(UserRole role);

    long countByEnabledTrue();

    long countByEnabledFalse();

    List<UserAccount> findTop5ByCreatedAtAfterOrderByCreatedAtDesc(
            java.time.LocalDateTime createdAfter
    );

    List<UserAccount> findAllByOrderByCreatedAtDesc();
}
