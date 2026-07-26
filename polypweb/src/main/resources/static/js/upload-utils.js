(function () {
    "use strict";

    const DEFAULT_MAX_SIZE = 10 * 1024 * 1024;
    const DEFAULT_TYPES = ["image/jpeg", "image/png"];

    function formatFileSize(bytes) {
        if (bytes < 1024 * 1024) {
            return `${(bytes / 1024).toFixed(1)} KB`;
        }
        return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
    }

    function create(config) {
        const form = document.getElementById(config.formId);
        const zone = document.getElementById(config.zoneId);
        const input = document.getElementById(config.inputId);
        const chooseButton = document.getElementById(config.chooseButtonId);
        const removeButton = document.getElementById(config.removeButtonId);
        const prompt = document.getElementById(config.promptId);
        const previewContainer = document.getElementById(config.previewContainerId);
        const previewImage = document.getElementById(config.previewImageId);
        const previewName = document.getElementById(config.previewNameId);
        const previewSize = document.getElementById(config.previewSizeId);
        const selectedActions = document.getElementById(config.selectedActionsId);
        const errorContainer = document.getElementById(config.errorId);

        if (!form || !zone || !input || !chooseButton || !removeButton || !prompt
            || !previewContainer || !previewImage || !previewName || !previewSize
            || !selectedActions || !errorContainer) {
            return null;
        }

        const acceptedTypes = config.acceptedTypes || DEFAULT_TYPES;
        const maxFileSize = config.maxFileSize || DEFAULT_MAX_SIZE;
        let selectedFile = null;
        let previewUrl = null;

        function validate(file) {
            if (!file) return config.missingMessage;
            if (!acceptedTypes.includes(file.type)) return config.typeMessage;
            if (file.size > maxFileSize) return config.sizeMessage;
            return "";
        }

        function showError(message) {
            const text = errorContainer.querySelector("span");
            if (text) text.textContent = message;
            errorContainer.hidden = false;
            zone.classList.add("has-error");
            input.setAttribute("aria-invalid", "true");
        }

        function clearError() {
            errorContainer.hidden = true;
            zone.classList.remove("has-error");
            input.removeAttribute("aria-invalid");
        }

        function revokePreview() {
            if (!previewUrl) return;
            URL.revokeObjectURL(previewUrl);
            previewUrl = null;
        }

        function reset() {
            selectedFile = null;
            input.value = "";
            prompt.hidden = false;
            previewContainer.hidden = true;
            selectedActions.hidden = true;
            previewImage.removeAttribute("src");
            revokePreview();
            clearError();
        }

        function display(file) {
            const error = validate(file);
            if (error) {
                reset();
                showError(error);
                return false;
            }

            selectedFile = file;
            clearError();
            revokePreview();
            previewUrl = URL.createObjectURL(file);
            previewImage.src = previewUrl;
            previewName.textContent = file.name;
            previewSize.textContent = formatFileSize(file.size);
            prompt.hidden = true;
            previewContainer.hidden = false;
            selectedActions.hidden = false;
            return true;
        }

        function setDroppedFile(file) {
            const transfer = new DataTransfer();
            transfer.items.add(file);
            input.files = transfer.files;
            display(file);
        }

        ["dragenter", "dragover"].forEach((eventName) => {
            zone.addEventListener(eventName, (event) => {
                event.preventDefault();
                event.stopPropagation();
                zone.classList.add("is-dragging");
            });
        });

        ["dragleave", "drop"].forEach((eventName) => {
            zone.addEventListener(eventName, (event) => {
                event.preventDefault();
                event.stopPropagation();
                zone.classList.remove("is-dragging");
            });
        });

        zone.addEventListener("drop", (event) => {
            const file = event.dataTransfer.files[0];
            if (file) setDroppedFile(file);
        });

        zone.addEventListener("click", (event) => {
            if (!event.target.closest("button")) input.click();
        });

        zone.addEventListener("keydown", (event) => {
            if (event.key === "Enter" || event.key === " ") {
                event.preventDefault();
                input.click();
            }
        });

        chooseButton.addEventListener("click", (event) => {
            event.stopPropagation();
            input.click();
        });
        removeButton.addEventListener("click", reset);
        input.addEventListener("change", () => display(input.files[0]));
        window.addEventListener("beforeunload", revokePreview);

        return {
            form,
            input,
            zone,
            validate,
            showError,
            clearError,
            reset,
            getFile: () => selectedFile || input.files[0] || null,
            focusError: () => chooseButton.focus()
        };
    }

    window.PolypVisionUpload = {create, formatFileSize};
})();
