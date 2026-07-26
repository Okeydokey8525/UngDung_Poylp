document.addEventListener("DOMContentLoaded", () => {
    const upload = window.PolypVisionUpload?.create({
        formId: "compareForm",
        zoneId: "compareUploadZone",
        inputId: "compareImageInput",
        chooseButtonId: "compareChooseFileButton",
        removeButtonId: "compareRemoveImageButton",
        promptId: "compareUploadPrompt",
        previewContainerId: "comparePreviewContainer",
        previewImageId: "compareImagePreview",
        previewNameId: "comparePreviewFileName",
        previewSizeId: "comparePreviewFileSize",
        selectedActionsId: "compareSelectedFileActions",
        errorId: "compareFileError",
        missingMessage: "Vui lòng chọn một ảnh trước khi so sánh.",
        typeMessage: "Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG.",
        sizeMessage: "Dung lượng ảnh vượt quá 10 MB."
    });

    if (!upload) return;

    const submitButton = document.getElementById("compareSubmitButton");
    const submitStatus = document.getElementById("compareSubmitStatus");
    let submitting = false;

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
            submitButton.disabled = false;
            upload.form.removeAttribute("aria-busy");
            return;
        }

        submitting = true;
        submitButton.disabled = true;
        submitButton.querySelector(".button-default").hidden = true;
        submitButton.querySelector(".button-loading").hidden = false;
        upload.form.setAttribute("aria-busy", "true");
        if (submitStatus) {
            submitStatus.textContent = "Đang lần lượt chạy Baseline và VMamba. Vui lòng không gửi lại biểu mẫu.";
        }
    });
});
