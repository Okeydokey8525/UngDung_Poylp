package com.polyp.polypweb.config;

import com.polyp.polypweb.document.UserAccount;
import com.polyp.polypweb.document.UserRole;
import com.polyp.polypweb.service.UserAccountService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
public class AdminSeedRunner implements ApplicationRunner {

    private static final Logger LOGGER = LoggerFactory.getLogger(AdminSeedRunner.class);

    private final UserAccountService userAccountService;
    private final String adminEmail;
    private final String adminPassword;
    private final String adminName;

    public AdminSeedRunner(
            UserAccountService userAccountService,
            @Value("${POLYPVISION_ADMIN_EMAIL:}") String adminEmail,
            @Value("${POLYPVISION_ADMIN_PASSWORD:}") String adminPassword,
            @Value("${POLYPVISION_ADMIN_NAME:}") String adminName) {
        this.userAccountService = userAccountService;
        this.adminEmail = adminEmail;
        this.adminPassword = adminPassword;
        this.adminName = adminName;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (adminEmail.isBlank() || adminPassword.isBlank() || adminName.isBlank()) {
            LOGGER.info("Bỏ qua admin seed vì chưa cung cấp đủ biến môi trường.");
            return;
        }
        UserAccount account = userAccountService.createAdminIfMissing(
                adminName,
                adminEmail,
                adminPassword
        );
        if (account.getRole() == UserRole.ADMIN) {
            LOGGER.info("Admin seed đã được kiểm tra hoặc tạo thành công.");
        } else {
            LOGGER.warn("Không seed admin vì email cấu hình đã thuộc một tài khoản không phải ADMIN.");
        }
    }
}
