document.addEventListener("DOMContentLoaded", () => {
    setupThemeSwitcher();

    document.querySelectorAll("[data-current-year]").forEach((element) => {
        element.textContent = new Date().getFullYear().toString();
    });

    setupHistoryDeletes();
    setupComparisonDeletes();
    setupAuthForms();
    setupPasswordToggles();
    setupInterfaceOnlyActions();
});

const THEME_STORAGE_KEY = "polypvision-theme";
const THEME_VALUES = ["light", "dark", "system"];
const THEME_LABELS = {
    light: "Sáng",
    dark: "Tối",
    system: "Theo hệ thống"
};
const THEME_ICONS = {
    light: "bi bi-sun",
    dark: "bi bi-moon-stars",
    system: "bi bi-display"
};

function readThemePreference() {
    try {
        const saved = localStorage.getItem(THEME_STORAGE_KEY);
        return THEME_VALUES.includes(saved) ? saved : "system";
    } catch (_) {
        return "system";
    }
}

function resolveTheme(preference, mediaQuery) {
    if (preference !== "system") return preference;
    return mediaQuery.matches ? "dark" : "light";
}

function setupThemeSwitcher() {
    const mediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    const options = document.querySelectorAll("[data-theme-option]");
    const currentIcon = document.querySelector("[data-theme-current-icon]");
    const currentLabel = document.querySelector("[data-theme-current-label]");
    const themeColor = document.querySelector('meta[name="theme-color"]');
    let preference = readThemePreference();

    const render = (persist) => {
        const resolved = resolveTheme(preference, mediaQuery);
        document.documentElement.setAttribute("data-bs-theme", resolved);
        document.documentElement.dataset.themePreference = preference;

        if (persist) {
            try {
                localStorage.setItem(THEME_STORAGE_KEY, preference);
            } catch (_) {
                // Giao diện vẫn đổi theme trong phiên hiện tại khi storage bị chặn.
            }
        }

        if (currentIcon) currentIcon.className = THEME_ICONS[preference];
        if (currentLabel) currentLabel.textContent = THEME_LABELS[preference];
        if (themeColor) themeColor.content = resolved === "dark" ? "#102a3b" : "#0b6bcb";

        options.forEach((option) => {
            const active = option.dataset.themeOption === preference;
            option.classList.toggle("active", active);
            option.setAttribute("aria-pressed", active.toString());
        });
    };

    options.forEach((option) => {
        option.addEventListener("click", () => {
            preference = option.dataset.themeOption;
            render(true);
        });
    });

    mediaQuery.addEventListener("change", () => {
        if (preference === "system") render(false);
    });

    render(false);
}

function setupHistoryDeletes() {
    document.querySelectorAll("[data-delete-history-form]").forEach((form) => {
        form.addEventListener("submit", (event) => {
            const confirmed = window.confirm("Bạn có chắc muốn xóa bản ghi này khỏi MongoDB?");
            if (!confirmed) {
                event.preventDefault();
            }
        });
    });
}

function setupComparisonDeletes() {
    document.querySelectorAll("[data-delete-comparison-form]").forEach((form) => {
        form.addEventListener("submit", (event) => {
            const confirmed = window.confirm(
                "Bạn có chắc muốn xóa toàn bộ phiên so sánh, gồm hai kết quả và ba file ảnh?"
            );
            if (!confirmed) {
                event.preventDefault();
            }
        });
    });
}

function setupAuthForms() {
    document.querySelectorAll("[data-auth-form]").forEach((form) => {
        form.addEventListener("submit", (event) => {
            if (form.hasAttribute("data-register-form")) {
                const password = form.querySelector("#password");
                const confirmation = form.querySelector("#confirmPassword");
                if (password && confirmation) {
                    confirmation.setCustomValidity(
                        password.value === confirmation.value ? "" : "Mật khẩu xác nhận chưa khớp."
                    );
                }
            }

            form.classList.add("was-validated");

            if (!form.checkValidity()) {
                event.preventDefault();
                event.stopPropagation();
                const firstInvalid = form.querySelector(":invalid");
                if (firstInvalid) firstInvalid.focus();
                form.removeAttribute("aria-busy");
                return;
            }

            const submitButton = form.querySelector('button[type="submit"]');
            const status = form.querySelector("[data-submit-status]");
            if (submitButton) {
                submitButton.disabled = true;
                submitButton.querySelector(".button-default")?.setAttribute("hidden", "");
                submitButton.querySelector(".button-loading")?.removeAttribute("hidden");
            }
            if (status) status.textContent = "Đang xử lý biểu mẫu, vui lòng chờ.";
            form.setAttribute("aria-busy", "true");
        });
    });
}

function setupPasswordToggles() {
    document.querySelectorAll("[data-password-toggle]").forEach((button) => {
        button.addEventListener("click", () => {
            const input = document.getElementById(button.dataset.passwordToggle);
            if (!input) {
                return;
            }

            const isPassword = input.type === "password";
            input.type = isPassword ? "text" : "password";
            button.setAttribute("aria-label", isPassword ? "Ẩn mật khẩu" : "Hiện mật khẩu");
            const icon = button.querySelector("i");
            if (icon) {
                icon.className = isPassword ? "bi bi-eye-slash" : "bi bi-eye";
            }
        });
    });
}

function setupInterfaceOnlyActions() {
    document.querySelectorAll("[data-ui-only-link]").forEach((link) => {
        link.addEventListener("click", (event) => {
            event.preventDefault();
            window.alert("Tính năng này sẽ được tích hợp ở giai đoạn xác thực tài khoản.");
        });
    });

    document.querySelectorAll("[data-mock-download]").forEach((button) => {
        button.addEventListener("click", () => {
            window.alert("Ảnh kết quả thật chưa có vì mô hình AI chưa được tích hợp.");
        });
    });
}
