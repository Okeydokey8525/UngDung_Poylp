package com.polyp.polypweb.service;

import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.dto.ChangePasswordForm;
import com.polyp.polypweb.dto.ProfileUpdateForm;
import com.polyp.polypweb.dto.RegisterForm;
import com.polyp.polypweb.exception.AccountOperationException;
import com.polyp.polypweb.exception.DuplicateEmailException;
import com.polyp.polypweb.repository.UserAccountRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserAccountServiceTests {

    @Mock
    private UserAccountRepository repository;

    private PasswordEncoder passwordEncoder;
    private UserAccountService service;

    @BeforeEach
    void setUp() {
        passwordEncoder = new BCryptPasswordEncoder(4);
        service = new UserAccountService(repository, passwordEncoder);
    }

    @Test
    void validRegistrationNormalizesEmailAndCreatesEnabledUser() {
        RegisterForm form = validRegistration();
        form.setEmail("  User@Example.COM ");
        when(repository.existsByEmailIgnoreCase("user@example.com")).thenReturn(false);
        when(repository.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));

        UserAccount saved = service.register(form);

        assertEquals("user@example.com", saved.getEmail());
        assertEquals("Nguyễn Văn A", saved.getFullName());
        assertEquals(UserRole.USER, saved.getRole());
        assertTrue(saved.isEnabled());
    }

    @Test
    void duplicateEmailCheckIsCaseInsensitiveAfterNormalization() {
        RegisterForm form = validRegistration();
        form.setEmail("EXISTING@EXAMPLE.COM");
        when(repository.existsByEmailIgnoreCase("existing@example.com")).thenReturn(true);

        assertThrows(DuplicateEmailException.class, () -> service.register(form));
        verify(repository, never()).save(any());
    }

    @Test
    void mismatchedPasswordIsRejected() {
        RegisterForm form = validRegistration();
        form.setConfirmPassword("Another123");

        assertThrows(AccountOperationException.class, () -> service.register(form));
    }

    @Test
    void weakPasswordIsRejected() {
        RegisterForm form = validRegistration();
        form.setPassword("password");
        form.setConfirmPassword("password");

        assertThrows(AccountOperationException.class, () -> service.register(form));
    }

    @Test
    void registrationAlwaysForcesUserRole() {
        RegisterForm form = validRegistration();
        when(repository.existsByEmailIgnoreCase(form.getEmail())).thenReturn(false);
        when(repository.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));

        UserAccount saved = service.register(form);

        assertEquals(UserRole.USER, saved.getRole());
    }

    @Test
    void passwordHashNeverEqualsRawPassword() {
        RegisterForm form = validRegistration();
        when(repository.existsByEmailIgnoreCase(form.getEmail())).thenReturn(false);
        when(repository.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));

        UserAccount saved = service.register(form);

        assertNotEquals(form.getPassword(), saved.getPasswordHash());
        assertTrue(passwordEncoder.matches(form.getPassword(), saved.getPasswordHash()));
    }

    @Test
    void changePasswordStoresNewBcryptHash() {
        UserAccount account = account("u1", UserRole.USER, true, "OldPass123");
        when(repository.findById("u1")).thenReturn(Optional.of(account));

        service.changePassword("u1", passwordChange("OldPass123", "NewPass456", "NewPass456"));

        assertTrue(passwordEncoder.matches("NewPass456", account.getPasswordHash()));
        assertFalse(passwordEncoder.matches("OldPass123", account.getPasswordHash()));
        verify(repository).save(account);
    }

    @Test
    void wrongCurrentPasswordIsRejected() {
        UserAccount account = account("u1", UserRole.USER, true, "OldPass123");
        when(repository.findById("u1")).thenReturn(Optional.of(account));

        assertThrows(
                AccountOperationException.class,
                () -> service.changePassword(
                        "u1",
                        passwordChange("WrongPass123", "NewPass456", "NewPass456")
                )
        );
        verify(repository, never()).save(any());
    }

    @Test
    void newPasswordConfirmationMustMatch() {
        UserAccount account = account("u1", UserRole.USER, true, "OldPass123");
        when(repository.findById("u1")).thenReturn(Optional.of(account));

        assertThrows(
                AccountOperationException.class,
                () -> service.changePassword(
                        "u1",
                        passwordChange("OldPass123", "NewPass456", "Different789")
                )
        );
    }

    @Test
    void newPasswordMustDifferFromCurrentPassword() {
        UserAccount account = account("u1", UserRole.USER, true, "OldPass123");
        when(repository.findById("u1")).thenReturn(Optional.of(account));

        assertThrows(
                AccountOperationException.class,
                () -> service.changePassword(
                        "u1",
                        passwordChange("OldPass123", "OldPass123", "OldPass123")
                )
        );
    }

    @Test
    void profileUpdateNormalizesEmailWithoutChangingIdentity() {
        UserAccount account = account("stable-id", UserRole.USER, true, "OldPass123");
        when(repository.findById("stable-id")).thenReturn(Optional.of(account));
        when(repository.findByEmailIgnoreCase("new@example.com")).thenReturn(Optional.empty());
        ProfileUpdateForm form = new ProfileUpdateForm();
        form.setFullName("  Nguyễn   Văn B  ");
        form.setEmail(" NEW@Example.com ");

        service.updateProfile("stable-id", form);

        assertEquals("stable-id", account.getId());
        assertEquals("Nguyễn Văn B", account.getFullName());
        assertEquals("new@example.com", account.getEmail());
    }

    @Test
    void adminCannotDisableSelf() {
        assertThrows(
                AccountOperationException.class,
                () -> service.toggleEnabled("admin-id", "admin-id")
        );
        verify(repository, never()).findById(any());
    }

    @Test
    void lastAdminCannotBeDemoted() {
        UserAccount account = account("admin-id", UserRole.ADMIN, true, "AdminPass123");
        when(repository.findById("admin-id")).thenReturn(Optional.of(account));
        when(repository.countByRole(UserRole.ADMIN)).thenReturn(1L);

        assertThrows(
                AccountOperationException.class,
                () -> service.changeRole("admin-id", "admin-id", UserRole.USER)
        );
        verify(repository, never()).save(any());
    }

    @Test
    void adminSeedCreatesBcryptAdminWithoutChangingExistingAccount() {
        when(repository.findByEmailIgnoreCase("admin@example.com")).thenReturn(Optional.empty());
        when(repository.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));

        UserAccount admin = service.createAdminIfMissing(
                "System Admin",
                "ADMIN@EXAMPLE.COM",
                "AdminPass123"
        );

        assertEquals(UserRole.ADMIN, admin.getRole());
        assertTrue(admin.isEnabled());
        assertTrue(passwordEncoder.matches("AdminPass123", admin.getPasswordHash()));
    }

    @Test
    void publicViewDoesNotExposePasswordHash() {
        UserAccount account = account("u1", UserRole.USER, true, "OldPass123");
        when(repository.findById("u1")).thenReturn(Optional.of(account));

        Object view = service.findViewById("u1");

        assertThrows(NoSuchMethodException.class, () -> view.getClass().getMethod("getPasswordHash"));
    }

    private RegisterForm validRegistration() {
        RegisterForm form = new RegisterForm();
        form.setFullName("Nguyễn Văn A");
        form.setEmail("user@example.com");
        form.setPassword("Password123");
        form.setConfirmPassword("Password123");
        form.setAcceptedTerms(true);
        return form;
    }

    private ChangePasswordForm passwordChange(
            String currentPassword,
            String newPassword,
            String confirmation) {
        ChangePasswordForm form = new ChangePasswordForm();
        form.setCurrentPassword(currentPassword);
        form.setNewPassword(newPassword);
        form.setConfirmNewPassword(confirmation);
        return form;
    }

    private UserAccount account(
            String id,
            UserRole role,
            boolean enabled,
            String rawPassword) {
        UserAccount account = new UserAccount();
        account.setId(id);
        account.setFullName("Test User");
        account.setEmail(id + "@example.com");
        account.setPasswordHash(passwordEncoder.encode(rawPassword));
        account.setRole(role);
        account.setEnabled(enabled);
        account.setCreatedAt(LocalDateTime.now());
        account.setUpdatedAt(LocalDateTime.now());
        return account;
    }
}
