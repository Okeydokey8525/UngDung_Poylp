import os
import time
from time import perf_counter

import pytest

import main
from test_video import fake_predict, make_video
import video_processing
from video_processing import process_video


@pytest.fixture
def short_video():
    path = make_video(1.0)  # 10 frames at 10 FPS
    yield path
    os.remove(path)


@pytest.fixture(autouse=True)
def clean_jobs():
    main.LIVE_JOBS.clear()
    yield
    main.LIVE_JOBS.clear()


def test_01_realtime_mode_releases_frames_at_source_rate_and_reports_each(short_video):
    events = []
    fake_predict.calls = 0
    started = perf_counter()
    analysis = process_video(short_video, 5, 60, fake_predict,
                             on_frame=lambda frame, event: events.append(event), realtime=True)
    elapsed = perf_counter() - started
    assert len(events) == analysis.frames_written == 10
    assert [e["frameIndex"] for e in events] == list(range(10))
    assert [e["analysed"] for e in events] == [True, False] * 5
    # Frame 9 is released no earlier than 0.9 s after the first one.
    assert elapsed >= 0.85


def test_02_offline_mode_is_never_paced(monkeypatch, short_video):
    sleeps = []
    monkeypatch.setattr(video_processing.time, "sleep", lambda seconds: sleeps.append(seconds))
    fake_predict.calls = 0
    process_video(short_video, 5, 60, fake_predict)
    assert sleeps == []


def start(client, path, **form):
    data = {"modelType": "YOLO26s-TSVM-FP32-seg", "sampleFps": "5", **form}
    with open(path, "rb") as handle:
        return client.post("/video/live", data=data,
                           files={"video": ("clip.avi", handle.read(), "video/x-msvideo")})


def wait_done(client, job_id, timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        body = client.get(f"/video/live/{job_id}/status").json()
        if body["state"] != "running":
            return body
        time.sleep(0.05)
    raise AssertionError("live job did not finish")


def test_03_live_job_runs_in_background_and_returns_the_offline_payload(app_client, monkeypatch, short_video):
    client, _ = app_client
    fake_predict.calls = 0
    monkeypatch.setattr(main, "predict_video_frame", lambda model, device, frame: fake_predict(frame))
    response = start(client, short_video)
    assert response.status_code == 202, response.text
    job_id = response.json()["jobId"]

    running = client.get(f"/video/live/{job_id}/result")
    assert running.status_code == 409

    status = wait_done(client, job_id)
    assert status["state"] == "done"
    assert status["framesDone"] == 10
    assert status["framesAnalysed"] == 5
    assert status["sourceFps"] == 10
    # Paced to the source rate: never faster than real time (a busy CI machine may fall behind).
    assert 0.3 < status["realtimeFactor"] <= 1.3

    result = client.get(f"/video/live/{job_id}/result")
    assert result.status_code == 200
    body = result.json()
    assert body["framesProcessed"] == 5
    assert body["framesWritten"] == 10
    assert body["modelType"] == "YOLO26s-TSVM-FP32-seg"
    assert body["resultVideoBase64"] and body["resultVideoId"] is None

    as_file = client.get(f"/video/live/{job_id}/result", params={"transfer": "file"}).json()
    assert as_file["resultVideoBase64"] == "" and as_file["framesProcessed"] == 5
    video = client.get(f"/video/result/{as_file['resultVideoId']}")
    assert video.status_code == 200 and len(video.content) == as_file["resultVideoBytes"]

    stream = client.get(f"/video/live/{job_id}/stream")
    assert stream.headers["content-type"].startswith("multipart/x-mixed-replace")
    assert b"--polypframe\r\nContent-Type: image/jpeg" in stream.content
    assert b"\xff\xd8" in stream.content  # JPEG start of image


def test_04_live_job_validates_like_offline_and_unknown_ids_are_404(app_client, short_video):
    client, _ = app_client
    assert start(client, short_video, sampleFps="7").status_code == 422
    assert client.get("/video/live/" + "0" * 32 + "/status").status_code == 404
    assert client.get("/video/live/not-a-job/result").status_code == 404


def test_05_unreadable_live_video_ends_in_error_with_422(app_client):
    client, _ = app_client
    response = client.post("/video/live", data={"modelType": "YOLO26s-seg"},
                           files={"video": ("clip.mp4", b"garbage bytes", "video/mp4")})
    assert response.status_code == 202
    job_id = response.json()["jobId"]
    status = wait_done(client, job_id)
    assert status["state"] == "error"
    assert client.get(f"/video/live/{job_id}/result").status_code == 422
