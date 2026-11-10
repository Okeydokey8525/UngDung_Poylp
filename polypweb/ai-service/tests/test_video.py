import base64
import os
import tempfile

import cv2
import numpy as np
import pytest

import main
import video_processing
from video_processing import FramePrediction, VideoProcessingError, process_video

WEBM_MAGIC = b"\x1a\x45\xdf\xa3"


def is_video(data: bytes) -> bool:
    """WebM (EBML header) or MP4 (ftyp box), depending on the encoder the platform offers."""
    return data[:4] == WEBM_MAGIC or data[4:8] == b"ftyp"


def make_video(seconds: float, fps: int = 10, size=(96, 64), suffix=".avi") -> str:
    handle, path = tempfile.mkstemp(suffix=suffix)
    os.close(handle)
    writer = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*"MJPG"), fps, size)
    assert writer.isOpened()
    for index in range(int(seconds * fps)):
        frame = np.full((size[1], size[0], 3), (index * 7) % 255, np.uint8)
        writer.write(frame)
    writer.release()
    return path


def fake_predict(frame):
    """Detect a polyp on every other call; overlay is the frame itself."""
    fake_predict.calls += 1
    detected = fake_predict.calls % 2 == 1
    return FramePrediction(
        detected=detected,
        confidence=0.8 if detected else 0.0,
        mask_count=1 if detected else 0,
        overlay_bgr=np.asarray(frame)[..., ::-1].copy(),
        inference_ms=3.0,
    )


@pytest.fixture
def video_path():
    path = make_video(3.0)
    yield path
    os.remove(path)


def test_01_process_video_samples_at_requested_rate(video_path):
    fake_predict.calls = 0
    analysis = process_video(video_path, 5, 60, fake_predict)
    assert analysis.source_fps == 10
    assert analysis.sample_fps == 5
    assert analysis.frames_processed == 15
    assert [p["frameIndex"] for p in analysis.timeline][:4] == [0, 2, 4, 6]
    assert analysis.frames_with_polyp == 8
    assert analysis.max_confidence == pytest.approx(0.8)
    assert is_video(analysis.video_bytes)
    assert analysis.video_mime_type in {"video/mp4", "video/webm"}
    assert len(analysis.segments) == 8
    assert analysis.segments[0] == {"startSec": 0.0, "endSec": 0.2, "frames": 1, "maxConfidence": 0.8}


def test_02_sample_rate_never_exceeds_source_rate(video_path):
    fake_predict.calls = 0
    analysis = process_video(video_path, 20, 60, fake_predict)
    assert analysis.sample_fps == 10
    assert analysis.frames_processed == 30


def test_03_too_long_video_is_rejected(video_path):
    fake_predict.calls = 0
    with pytest.raises(VideoProcessingError):
        process_video(video_path, 5, 1, fake_predict)


def test_04_unreadable_file_is_rejected():
    handle, path = tempfile.mkstemp(suffix=".mp4")
    os.write(handle, b"not a video at all")
    os.close(handle)
    try:
        with pytest.raises(VideoProcessingError):
            process_video(path, 5, 60, fake_predict)
    finally:
        os.remove(path)


def test_05_segments_merge_consecutive_detections():
    timeline = [
        {"timeSec": 0.0, "detected": True, "confidence": 0.5},
        {"timeSec": 0.2, "detected": True, "confidence": 0.9},
        {"timeSec": 0.4, "detected": False, "confidence": 0.0},
        {"timeSec": 0.6, "detected": True, "confidence": 0.7},
    ]
    segments = video_processing._segments(timeline, 0.2)
    assert segments == [
        {"startSec": 0.0, "endSec": 0.4, "frames": 2, "maxConfidence": 0.9},
        {"startSec": 0.6, "endSec": 0.8, "frames": 1, "maxConfidence": 0.7},
    ]


def post_video(client, path, **form):
    data = {"modelType": "YOLO26s-TSVM-FP32-seg", "sampleFps": "5", **form}
    with open(path, "rb") as handle:
        return client.post(
            "/video/predict",
            data=data,
            files={"video": ("clip.avi", handle.read(), "video/x-msvideo")},
        )


def test_06_endpoint_returns_timeline_and_webm(app_client, monkeypatch, video_path):
    client, _ = app_client
    fake_predict.calls = 0
    monkeypatch.setattr(main, "predict_video_frame", lambda model, device, frame: fake_predict(frame))
    response = post_video(client, video_path)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["modelType"] == "YOLO26s-TSVM-FP32-seg"
    assert body["framesProcessed"] == 15
    assert body["framesWithPolyp"] == 8
    assert body["resultVideoMimeType"] in {"video/mp4", "video/webm"}
    assert is_video(base64.b64decode(body["resultVideoBase64"]))
    assert len(body["timeline"]) == 15
    assert body["averageInferenceMs"] == pytest.approx(3.0)


def test_06b_file_transfer_returns_id_and_serves_the_video_once(app_client, monkeypatch, video_path):
    client, _ = app_client
    fake_predict.calls = 0
    monkeypatch.setattr(main, "predict_video_frame", lambda model, device, frame: fake_predict(frame))
    response = post_video(client, video_path, resultVideoTransfer="file")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["resultVideoBase64"] == ""
    assert body["resultVideoBytes"] > 0
    video_id = body["resultVideoId"]
    assert len(video_id) == 32
    download = client.get(f"/video/result/{video_id}")
    assert download.status_code == 200
    assert download.headers["content-type"] == body["resultVideoMimeType"]
    assert len(download.content) == body["resultVideoBytes"]
    assert is_video(download.content)
    assert client.get(f"/video/result/{video_id}").status_code == 404  # served once
    assert client.get("/video/result/not-an-id").status_code == 404
    assert post_video(client, video_path, resultVideoTransfer="ftp").status_code == 422

def test_07_endpoint_rejects_bad_sample_rate_and_extension(app_client, video_path):
    client, _ = app_client
    assert post_video(client, video_path, sampleFps="7").status_code == 422
    with open(video_path, "rb") as handle:
        response = client.post(
            "/video/predict",
            data={"modelType": "YOLO26s-seg"},
            files={"video": ("clip.exe", handle.read(), "application/x-msdownload")},
        )
    assert response.status_code == 415


def test_08_endpoint_maps_unreadable_video_to_422(app_client):
    client, _ = app_client
    response = client.post(
        "/video/predict",
        data={"modelType": "YOLO26s-seg"},
        files={"video": ("clip.mp4", b"garbage bytes", "video/mp4")},
    )
    assert response.status_code == 422


def test_09_frame_cap_lowers_sample_rate_but_covers_whole_video(video_path):
    fake_predict.calls = 0
    analysis = process_video(video_path, 10, 60, fake_predict, max_frames=6)
    assert analysis.sample_rate_reduced is True
    assert analysis.requested_sample_fps == 10
    assert analysis.sample_fps == pytest.approx(2.0)
    assert analysis.frames_processed == 6
    assert analysis.timeline[-1]["timeSec"] == pytest.approx(2.5)


def test_10_endpoint_reports_reduced_rate_and_enforces_size(app_client, monkeypatch, video_path):
    client, _ = app_client
    fake_predict.calls = 0
    monkeypatch.setattr(main, "predict_video_frame", lambda model, device, frame: fake_predict(frame))
    monkeypatch.setattr(main, "MAX_VIDEO_FRAMES", 6)
    body = post_video(client, video_path, sampleFps="10").json()
    assert body["sampleRateReduced"] is True
    assert body["requestedSampleFps"] == 10
    assert body["framesProcessed"] == 6

    monkeypatch.setattr(main, "MAX_VIDEO_FILE_SIZE", 1024)
    assert post_video(client, video_path).status_code == 413


def count_frames(video_bytes: bytes) -> tuple[int, float]:
    handle, path = tempfile.mkstemp(suffix=".mp4" if video_bytes[4:8] == b"ftyp" else ".webm")
    os.write(handle, video_bytes)
    os.close(handle)
    try:
        capture = cv2.VideoCapture(path)
        fps = capture.get(cv2.CAP_PROP_FPS)
        frames = 0
        while capture.read()[0]:
            frames += 1
        capture.release()
        return frames, fps
    finally:
        os.remove(path)


def test_11_output_keeps_every_source_frame_and_holds_the_last_mask(video_path):
    rendered = []

    def predict_with_render(frame):
        prediction = fake_predict(frame)
        prediction.render = lambda frame_bgr, call=fake_predict.calls: rendered.append(call) or frame_bgr
        return prediction

    fake_predict.calls = 0
    analysis = process_video(video_path, 5, 60, predict_with_render)
    assert analysis.frames_processed == 15
    assert analysis.frames_written == 30
    assert analysis.frames_held == 15
    assert analysis.output_fps == 10
    # Each held frame is drawn with the prediction of the sample right before it.
    assert rendered == list(range(1, 16))
    frames, fps = count_frames(analysis.video_bytes)
    assert frames == 30
    assert fps == pytest.approx(10, abs=0.01)


def test_12_all_frames_mode_analyses_every_frame(video_path):
    fake_predict.calls = 0
    analysis = process_video(video_path, video_processing.ALL_FRAMES, 60, fake_predict)
    assert analysis.requested_sample_fps == 0
    assert analysis.sample_fps == 10
    assert analysis.frames_processed == 30
    assert analysis.frames_held == 0
    assert analysis.frames_written == 30


def test_14_webm_fallback_when_mp4_is_forced_off(monkeypatch, video_path):
    monkeypatch.setattr(video_processing, "OUTPUT_ORDER", ("webm",))
    fake_predict.calls = 0
    analysis = process_video(video_path, 5, 60, fake_predict)
    assert analysis.video_mime_type == "video/webm"
    assert analysis.video_bytes[:4] == WEBM_MAGIC
    assert count_frames(analysis.video_bytes)[0] == 30


def test_13_all_frames_mode_needs_gpu(app_client, monkeypatch, video_path):
    client, _ = app_client
    fake_predict.calls = 0
    monkeypatch.setattr(main, "predict_video_frame", lambda model, device, frame: fake_predict(frame))
    monkeypatch.setattr(main.app.state, "device", "cpu")
    response = post_video(client, video_path, sampleFps="0")
    assert response.status_code == 422
    assert "GPU" in response.json()["detail"]

    monkeypatch.setattr(main.app.state, "device", "cuda:0")
    body = post_video(client, video_path, sampleFps="0").json()
    assert body["framesProcessed"] == 30
    assert body["framesHeld"] == 0
    assert body["outputFps"] == 10
    assert body["framesWritten"] == 30
