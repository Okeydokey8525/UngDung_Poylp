document.addEventListener("DOMContentLoaded", () => {
    const upload = window.PolypVisionUpload?.create({
        formId: "diagnoseForm",
        zoneId: "uploadZone",
        inputId: "imageInput",
        chooseButtonId: "chooseFileButton",
        removeButtonId: "removeImageButton",
        promptId: "uploadPrompt",
        previewContainerId: "previewContainer",
        previewImageId: "imagePreview",
        previewNameId: "previewFileName",
        previewSizeId: "previewFileSize",
        selectedActionsId: "selectedFileActions",
        errorId: "fileError",
        missingMessage: "Vui lòng chọn một ảnh trước khi phân tích.",
        typeMessage: "Tệp không hợp lệ. Vui lòng chọn ảnh JPG, JPEG hoặc PNG.",
        sizeMessage: "Dung lượng ảnh vượt quá 10 MB. Vui lòng chọn tệp nhỏ hơn."
    });

    if (!upload) return;

    const modelSelect = document.getElementById("modelType");
    const modelCategory = document.getElementById("modelCategory");
    const modelDescription = document.getElementById("modelDescriptionText");
    const analyzeButton = document.getElementById("analyzeButton");
    const submitStatus = document.getElementById("diagnoseSubmitStatus");
    let submitting = false;

    const updateModelDescription = () => {
        const option = modelSelect.options[modelSelect.selectedIndex];
        const usesVmamba = option.dataset.vmamba === "true";
        modelCategory.textContent = usesVmamba ? "Tích hợp VMambaBlock" : "Baseline";
        modelDescription.textContent = option.dataset.description || "";
    };

    modelSelect.addEventListener("change", updateModelDescription);
    updateModelDescription();

    upload.form.addEventListener("submit", (event) => {
        if (submitting) {
            event.preventDefault();
            return;
        }

        const error = upload.validate(upload.getFile());
        if (error) {
            event.preventDefault();
            upload.showError(error);
            upload.focusError();
            analyzeButton.disabled = false;
            upload.form.removeAttribute("aria-busy");
            return;
        }

        submitting = true;
        analyzeButton.disabled = true;
        analyzeButton.querySelector(".button-default").hidden = true;
        analyzeButton.querySelector(".button-loading").hidden = false;
        upload.form.setAttribute("aria-busy", "true");
        if (submitStatus) {
            submitStatus.textContent = "Đang gửi ảnh và chờ mô hình xử lý. Vui lòng không gửi lại biểu mẫu.";
        }
    });
});
