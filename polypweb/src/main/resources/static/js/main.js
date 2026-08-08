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

function setupRegisterValidation(form) {
    const fields = Array.from(form.querySelectorAll("input[aria-describedby]"));
    const password = form.querySelector("#password");
    const confirmation = form.querySelector("#confirmPassword");

    const syncBlankValue = (field) => {
        if (field === confirmation || field.type === "checkbox") return;
        const whitespaceOnly = field.value.length > 0 && field.value.trim().length === 0;
        field.setCustomValidity(whitespaceOnly ? field.dataset.requiredMessage : "");
    };

    const syncPasswordConfirmation = () => {
        if (!password || !confirmation) return;
        if (confirmation.value.length > 0 && confirmation.value.trim().length === 0) {
            confirmation.setCustomValidity(confirmation.dataset.requiredMessage);
            return;
        }
        const mismatch = confirmation.value.length > 0 && password.value !== confirmation.value;
        confirmation.setCustomValidity(mismatch ? confirmation.dataset.mismatchMessage : "");
    };

    const feedbackFor = (field) => field.getAttribute("aria-describedby")
        ?.split(/\s+/)
        .map((id) => document.getElementById(id))
        .find((element) => element?.classList.contains("invalid-feedback"));

    const validationMessageFor = (field) => {
        if (field.validity.valueMissing) return field.dataset.requiredMessage;
        if (field.validity.typeMismatch) return field.dataset.typeMessage;
        if (field.validity.tooShort || field.validity.tooLong) {
            return field.dataset.lengthMessage || field.dataset.patternMessage;
        }
        if (field.validity.patternMismatch) return field.dataset.patternMessage;
        if (field.validity.customError) {
            return field.validationMessage;
        }
        return "Giá trị chưa hợp lệ.";
    };

    const renderFieldValidity = (field, force = false) => {
        const hadServerError = field.classList.contains("is-invalid");
        if (!force && field.dataset.validationTouched !== "true" && !hadServerError) return;

        syncBlankValue(field);
        const invalid = !field.checkValidity();
        field.classList.toggle("is-invalid", invalid);
        field.setAttribute("aria-invalid", invalid.toString());
        if (invalid) {
            const feedback = feedbackFor(field);
            if (feedback) feedback.textContent = validationMessageFor(field);
        }
    };

    const renderPasswordPair = (force = false) => {
        syncPasswordConfirmation();
        if (password) renderFieldValidity(password, force);
        if (confirmation) renderFieldValidity(confirmation, force);
    };

    fields.forEach((field) => {
        field.addEventListener("blur", () => {
            field.dataset.validationTouched = "true";
            if (field === password || field === confirmation) {
                renderPasswordPair(false);
            } else {
                renderFieldValidity(field, true);
            }
        });

        const eventName = field.type === "checkbox" ? "change" : "input";
        field.addEventListener(eventName, () => {
            if (field === password || field === confirmation) {
                renderPasswordPair(false);
            } else {
                renderFieldValidity(field, false);
            }
        });
    });

    return () => {
        syncPasswordConfirmation();
        fields.forEach((field) => {
            field.dataset.validationTouched = "true";
            renderFieldValidity(field, true);
        });
    };
}

function setupAuthForms() {
    document.querySelectorAll("[data-auth-form]").forEach((form) => {
        const validateRegister = form.hasAttribute("data-register-form")
            ? setupRegisterValidation(form)
            : null;

        form.addEventListener("submit", (event) => {
            validateRegister?.();

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
            button.setAttribute("aria-pressed", isPassword.toString());
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
