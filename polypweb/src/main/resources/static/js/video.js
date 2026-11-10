(function () {
    "use strict";

    var MAX_BYTES = 200 * 1024 * 1024;
    var MAX_SECONDS = 300;
    var ALLOWED = ["mp4", "avi", "mov", "mkv", "webm"];

    // Upload page: client-side checks, local preview and a busy state while the server works.
    var form = document.getElementById("videoForm");
    if (form) {
        var input = document.getElementById("videoInput");
        var error = document.getElementById("videoError");
        var previewWrap = document.getElementById("videoPreviewWrap");
        var preview = document.getElementById("videoPreview");
        var info = document.getElementById("videoPreviewInfo");
        var submit = document.getElementById("videoSubmit");
        var status = document.getElementById("videoSubmitStatus");
        var objectUrl = null;
        var previewNote = document.getElementById("videoPreviewNote");
        var previewTimer = null;

        // Browsers decode only H.264/VP8/VP9/AV1. Endoscope recordings are often MPEG-4 Part 2 (mp4v) or
        // MJPEG: the <video> stays black at 0:00. Say so instead of showing an empty player; the AI service
        // reads these files with OpenCV and the overlay video it returns always plays.
        var showUndecodable = function () {
            window.clearTimeout(previewTimer);
            preview.hidden = true;
            previewNote.hidden = false;
        };

        var showError = function (message) {
            error.querySelector("span").textContent = message;
            error.hidden = false;
        };

        var validate = function () {
            error.hidden = true;
            var file = input.files && input.files[0];
            if (!file) {
                showError("Vui lòng chọn một video.");
                return false;
            }
            var extension = file.name.split(".").pop().toLowerCase();
            if (ALLOWED.indexOf(extension) < 0) {
                showError("Chỉ hỗ trợ video MP4, AVI, MOV, MKV hoặc WEBM.");
                return false;
            }
            if (file.size > MAX_BYTES) {
                showError("Video vượt quá 200 MB.");
                return false;
            }
            return true;
        };

        input.addEventListener("change", function () {
            if (objectUrl) {
                URL.revokeObjectURL(objectUrl);
                objectUrl = null;
            }
            previewWrap.hidden = true;
            window.clearTimeout(previewTimer);
            preview.hidden = false;
            previewNote.hidden = true;
            if (!validate()) {
                return;
            }
            var file = input.files[0];
            objectUrl = URL.createObjectURL(file);
            preview.src = objectUrl;
            info.textContent = file.name + " · " + (file.size / 1024 / 1024).toFixed(1).replace(".", ",") + " MB";
            previewWrap.hidden = false;
            // A local file normally reports its metadata within a second; no metadata means no decoder.
            previewTimer = window.setTimeout(function () {
                if (preview.readyState < 1) {
                    showUndecodable();
                }
            }, 4000);
        });

        preview.addEventListener("error", showUndecodable);

        preview.addEventListener("loadeddata", function () {
            window.clearTimeout(previewTimer);
        });

        preview.addEventListener("loadedmetadata", function () {
            if (preview.videoWidth === 0) {
                showUndecodable();
                return;
            }
            if (isFinite(preview.duration) && preview.duration > MAX_SECONDS + 0.5) {
                showError("Video dài " + Math.round(preview.duration) + " giây, vượt giới hạn 5 phút; hãy cắt thành nhiều đoạn.");
            }
        });

        form.addEventListener("submit", function (event) {
            if (!validate()) {
                event.preventDefault();
                return;
            }
            submit.disabled = true;
            submit.querySelector(".button-default").hidden = true;
            var loading = submit.querySelector(".button-loading");
            loading.hidden = false;
            var live = document.getElementById("modeLive");
            if (live && live.checked) {
                // Live mode only waits for the upload; the page then switches to the live view.
                loading.lastChild.textContent = " Đang tải video lên, sắp chuyển sang xem trực tiếp...";
                status.textContent = "Đang tải video lên.";
            } else {
                status.textContent = "Đang phân tích video.";
            }
        });
    }

    // Result page: the stored original may use a codec the browser cannot play (see showUndecodable).
    var originalVideo = document.getElementById("originalVideo");
    if (originalVideo) {
        var originalNote = document.getElementById("originalVideoNote");
        var hideOriginal = function () {
            originalVideo.hidden = true;
            originalNote.hidden = false;
        };
        originalVideo.addEventListener("error", hideOriginal);
        originalVideo.addEventListener("loadedmetadata", function () {
            if (originalVideo.videoWidth === 0) {
                hideOriginal();
            }
        });
        if (originalVideo.error) {
            hideOriginal();
        }
    }

    // Result page: clicking a timeline tick or a segment seeks the overlay video.
    var resultVideo = document.getElementById("resultVideo");
    if (resultVideo) {
        var ticks = Array.prototype.slice.call(document.querySelectorAll(".timeline-tick"));
        var tickTimes = ticks.map(function (tick) {
            return parseFloat(tick.getAttribute("data-time")) || 0;
        });
        var seekTo = function (seconds) {
            resultVideo.currentTime = Math.max(0, seconds);
            resultVideo.focus();
        };
        ticks.forEach(function (tick) {
            tick.addEventListener("click", function () {
                // Ticks carry the source time of the analysed frame; the overlay video keeps that timing.
                seekTo(parseFloat(tick.getAttribute("data-time")) || 0);
            });
        });
        Array.prototype.forEach.call(document.querySelectorAll(".segment-seek"), function (button) {
            button.addEventListener("click", function () {
                seekTo(parseFloat(button.getAttribute("data-time")));
            });
        });
        resultVideo.addEventListener("timeupdate", function () {
            // Highlight the last analysed frame at or before the playback position.
            var now = resultVideo.currentTime + 1e-3;
            var lo = 0, hi = tickTimes.length - 1, current = -1;
            while (lo <= hi) {
                var mid = (lo + hi) >> 1;
                if (tickTimes[mid] <= now) { current = mid; lo = mid + 1; } else { hi = mid - 1; }
            }
            ticks.forEach(function (tick, index) {
                tick.classList.toggle("current", index === current);
            });
        });
    }
})();
