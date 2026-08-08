package com.polyp.polypweb.service;

import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.dto.ChangePasswordForm;
import com.polyp.polypweb.dto.ProfileUpdateForm;
import com.polyp.polypweb.dto.RegisterForm;
import com.polyp.polypweb.exception.AccountOperationException;
import com.polyp.polypweb.exception.DuplicateEmailException;
import com.polyp.polypweb.exception.PasswordOperationException;
import com.polyp.polypweb.repository.UserAccountRepository;
import com.polyp.polypweb.view.UserAccountView;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Pattern;

@Service
public class UserAccountService {

    private static final Pattern PASSWORD_PATTERN =
            Pattern.compile("^(?=.*[A-Za-z])(?=.*\\d).{8,72}$");

    private final UserAccountRepository repository;
    private final PasswordEncoder passwordEncoder;

    public UserAccountService(
            UserAccountRepository repository,
            PasswordEncoder passwordEncoder) {
        this.repository = repository;
        this.passwordEncoder = passwordEncoder;
    }

    public UserAccount register(RegisterForm form) {
        String email = normalizeEmail(form.getEmail());
        if (!form.isAcceptedTerms()) {
            throw new AccountOperationException("Bạn cần đồng ý với điều khoản sử dụng.");
        }
        if (form.getPassword() == null || !form.getPassword().equals(form.getConfirmPassword())) {
            throw new AccountOperationException("Mật khẩu xác nhận chưa khớp.");
        }
        validatePassword(form.getPassword());
        if (repository.existsByEmailIgnoreCase(email)) {
            throw new DuplicateEmailException();
        }

        LocalDateTime now = LocalDateTime.now();
        UserAccount account = new UserAccount();
        account.setFullName(normalizeFullName(form.getFullName()));
        account.setEmail(email);
        account.setPasswordHash(passwordEncoder.encode(form.getPassword()));
        account.setRole(UserRole.USER);
        account.setEnabled(true);
        account.setCreatedAt(now);
        account.setUpdatedAt(now);
        try {
            return repository.save(account);
        } catch (DuplicateKeyException exception) {
            throw new DuplicateEmailException();
        }
    }

    public Optional<UserAccount> findByEmail(String email) {
        return repository.findByEmailIgnoreCase(normalizeEmail(email));
    }

    public UserAccount findById(String id) {
        return repository.findById(id)
                .orElseThrow(() -> new AccountOperationException("Không tìm thấy tài khoản."));
    }

    public UserAccountView findViewById(String id) {
        return toView(findById(id));
    }

    public List<UserAccountView> findAllViews() {
        return repository.findAllByOrderByCreatedAtDesc()
                .stream()
                .map(this::toView)
                .toList();
    }

    public UserAccount updateProfile(String userId, ProfileUpdateForm form) {
        UserAccount account = findById(userId);
        String normalizedEmail = normalizeEmail(form.getEmail());
        repository.findByEmailIgnoreCase(normalizedEmail)
                .filter(existing -> !existing.getId().equals(userId))
                .ifPresent(existing -> {
                    throw new DuplicateEmailException();
                });
        account.setFullName(normalizeFullName(form.getFullName()));
        account.setEmail(normalizedEmail);
        account.setUpdatedAt(LocalDateTime.now());
        try {
            return repository.save(account);
        } catch (DuplicateKeyException exception) {
            throw new DuplicateEmailException();
        }
    }

    public void changePassword(String userId, ChangePasswordForm form) {
        UserAccount account = findById(userId);
        if (!passwordEncoder.matches(form.getCurrentPassword(), account.getPasswordHash())) {
            throw new PasswordOperationException(
                    "CURRENT_PASSWORD_INCORRECT",
                    "Mật khẩu hiện tại không đúng."
            );
        }
        if (form.getNewPassword() == null
                || !form.getNewPassword().equals(form.getConfirmNewPassword())) {
            throw new AccountOperationException("Mật khẩu mới xác nhận chưa khớp.");
        }
        validatePassword(form.getNewPassword());
        if (passwordEncoder.matches(form.getNewPassword(), account.getPasswordHash())) {
            throw new PasswordOperationException(
                    "PASSWORD_REUSE_NOT_ALLOWED",
                    "Mật khẩu mới phải khác mật khẩu hiện tại."
            );
        }
        account.setPasswordHash(passwordEncoder.encode(form.getNewPassword()));
        account.setUpdatedAt(LocalDateTime.now());
        repository.save(account);
    }

    public boolean toggleEnabled(String actorId, String targetId) {
        if (actorId.equals(targetId)) {
            throw new AccountOperationException("Bạn không thể tự khóa tài khoản đang sử dụng.");
        }
        UserAccount target = findById(targetId);
        if (target.getRole() == UserRole.ADMIN
                && target.isEnabled()
                && repository.countByRoleAndEnabledTrue(UserRole.ADMIN) <= 1) {
            throw new AccountOperationException("Không thể khóa quản trị viên hoạt động cuối cùng.");
        }
        target.setEnabled(!target.isEnabled());
        target.setUpdatedAt(LocalDateTime.now());
        repository.save(target);
        return target.isEnabled();
    }

    public void changeRole(String actorId, String targetId, UserRole role) {
        UserAccount target = findById(targetId);
        if (target.getRole() == UserRole.ADMIN
                && role == UserRole.USER
                && repository.countByRole(UserRole.ADMIN) <= 1) {
            throw new AccountOperationException("Không thể hạ quyền quản trị viên cuối cùng.");
        }
        target.setRole(role);
        target.setUpdatedAt(LocalDateTime.now());
        repository.save(target);
    }

    public UserAccount createAdminIfMissing(String fullName, String email, String password) {
        String normalizedEmail = normalizeEmail(email);
        Optional<UserAccount> existing = repository.findByEmailIgnoreCase(normalizedEmail);
        if (existing.isPresent()) {
            return existing.get();
        }
        validatePassword(password);
        LocalDateTime now = LocalDateTime.now();
        UserAccount account = new UserAccount();
        account.setFullName(normalizeFullName(fullName));
        account.setEmail(normalizedEmail);
        account.setPasswordHash(passwordEncoder.encode(password));
        account.setRole(UserRole.ADMIN);
        account.setEnabled(true);
        account.setCreatedAt(now);
        account.setUpdatedAt(now);
        try {
            return repository.save(account);
        } catch (DuplicateKeyException exception) {
            return repository.findByEmailIgnoreCase(normalizedEmail)
                    .orElseThrow(DuplicateEmailException::new);
        }
    }

    public static String normalizeEmail(String email) {
        if (email == null) {
            return "";
        }
        return email.trim().toLowerCase(Locale.ROOT);
    }

    private String normalizeFullName(String fullName) {
        if (fullName == null) {
            return "";
        }
        return fullName.trim().replaceAll("\\s+", " ");
    }

    private void validatePassword(String password) {
        if (password == null || !PASSWORD_PATTERN.matcher(password).matches()) {
            throw new AccountOperationException(
                    "Mật khẩu phải có 8–72 ký tự, gồm ít nhất một chữ và một số."
            );
        }
    }

    private UserAccountView toView(UserAccount account) {
        return new UserAccountView(
                account.getId(),
                account.getFullName(),
                account.getEmail(),
                account.getRole(),
                account.isEnabled(),
                account.getCreatedAt()
        );
    }
}
