(function () {
    "use strict";

    // Live page: poll the session status, show progress and the current detection, open the saved result.
    var panel = document.getElementById("livePanel");
    if (!panel) {
        return;
    }
    var statusUrl = panel.getAttribute("data-status-url");
    var resultUrl = panel.getAttribute("data-result-url");
    var badge = document.getElementById("liveDetect");
    var progress = document.getElementById("liveProgress");
    var progressBar = document.getElementById("liveProgressBar");
    var timeText = document.getElementById("liveTime");
    var speed = document.getElementById("liveSpeed");
    var frames = document.getElementById("liveFrames");
    var positive = document.getElementById("livePositive");
    var errorText = document.getElementById("liveError");
    var POLL_MS = 400;
    var failures = 0;

    var decimal = function (value, digits) {
        return (Number(value) || 0).toFixed(digits).replace(".", ",");
    };

    var setBadge = function (kind, icon, text) {
        badge.className = "result-status-badge live-detect-badge " + kind;
        badge.innerHTML = "";
        var i = document.createElement("i");
        i.className = "bi " + icon;
        var span = document.createElement("span");
        span.textContent = text;
        badge.appendChild(i);
        badge.appendChild(document.createTextNode(" "));
        badge.appendChild(span);
    };

    var render = function (s) {
        var total = Number(s.totalFrames) || 0;
        var done = Number(s.framesDone) || 0;
        var percent = total > 0 ? Math.min(100, 100 * done / total) : 0;
        progress.style.width = percent.toFixed(1) + "%";
        progressBar.setAttribute("aria-valuenow", percent.toFixed(0));
        timeText.textContent = decimal(s.videoTimeSec, 1) + " / " + decimal(s.durationSec, 1) + " giây";
        frames.textContent = done + (total > 0 ? " / " + total : "");
        positive.textContent = (s.framesWithPolyp || 0) + " / " + (s.framesAnalysed || 0);
        var factor = Number(s.realtimeFactor) || 0;
        if (done > 0) {
            speed.textContent = factor >= 0.95
                ? "Kịp thời gian thực (" + decimal(s.sourceFps, 0) + " khung/giây)"
                : "Chậm hơn " + decimal(1 / Math.max(factor, 0.01), 1) + " lần";
        }
        if (s.state === "running") {
            if (s.currentDetected) {
                setBadge("detected", "bi-exclamation-diamond-fill",
                    "Phát hiện polyp · " + decimal(100 * s.currentConfidence, 0) + "%");
            } else if (done > 0) {
                setBadge("clear", "bi-check-circle-fill", "Không thấy vùng nghi ngờ");
            }
        }
    };

    var poll = function () {
        fetch(statusUrl, {credentials: "same-origin", headers: {"Accept": "application/json"}})
            .then(function (response) {
                if (!response.ok) {
                    throw new Error("HTTP " + response.status);
                }
                return response.json();
            })
            .then(function (s) {
                failures = 0;
                render(s);
                if (s.state === "saved" && s.savedVideoId) {
                    setBadge("clear", "bi-check2-all", "Đã phát xong, đang mở kết quả");
                    window.location.assign(resultUrl + encodeURIComponent(s.savedVideoId));
                    return;
                }
                if (s.state === "error") {
                    setBadge("detected", "bi-x-octagon-fill", "Không hoàn thành");
                    errorText.textContent = s.error || "Phiên mô phỏng không hoàn thành.";
                    errorText.hidden = false;
                    return;
                }
                if (s.state === "done") {
                    setBadge("clear", "bi-hourglass-split", "Đang lưu kết quả");
                }
                window.setTimeout(poll, POLL_MS);
            })
            .catch(function () {
                failures += 1;
                if (failures >= 10) {
                    errorText.textContent = "Mất kết nối tới máy chủ. Tải lại trang để xem tiếp.";
                    errorText.hidden = false;
                    return;
                }
                window.setTimeout(poll, POLL_MS * 2);
            });
    };
    poll();
})();
