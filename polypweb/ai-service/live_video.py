"""Real-time playback simulation for recorded videos (web demo).

A live job runs the normal offline video pipeline in the background with ``realtime=True`` so frames
are released at the source frame rate. Every written frame (analysed or with the held mask) is JPEG
encoded and published here; the browser watches it as an MJPEG stream while the overlay video is
being written. When the job finishes, the same response as ``POST /video/predict`` is kept until the
web client collects it.

This is a simulation on a recorded file, not a real-time system attached to an endoscope.
"""
from __future__ import annotations

import threading
import time
import uuid
from dataclasses import dataclass, field
from time import perf_counter
from typing import Any

import cv2
import numpy as np

JPEG_QUALITY = 80
FINISHED_JOB_TTL_SEC = 30 * 60
MAX_JOBS = 16


@dataclass
class LiveJob:
    job_id: str
    model_type: str
    file_name: str
    requested_sample_fps: int
    state: str = "running"  # running | done | error
    created_at: float = field(default_factory=time.monotonic)
    first_frame_at: float | None = None
    last_frame_at: float | None = None
    finished_at: float | None = None
    source_fps: float = 0.0
    total_frames: int = 0
    frames_done: int = 0
    frames_analysed: int = 0
    frames_with_polyp: int = 0
    video_time_sec: float = 0.0
    current_detected: bool = False
    current_confidence: float = 0.0
    jpeg: bytes = b""
    seq: int = 0
    result: Any = None
    error: str | None = None
    error_status: int | None = None
    task: Any = None  # keeps the asyncio task referenced while it runs
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def push(self, frame_bgr: np.ndarray, event: dict) -> None:
        """Called from the worker thread for every frame written to the overlay video."""
        ok, buffer = cv2.imencode(".jpg", frame_bgr, [cv2.IMWRITE_JPEG_QUALITY, JPEG_QUALITY])
        now = perf_counter()
        with self._lock:
            if self.first_frame_at is None:
                self.first_frame_at = now
            self.last_frame_at = now
            if ok:
                self.jpeg = buffer.tobytes()
                self.seq += 1
            self.source_fps = event["sourceFps"]
            self.total_frames = event["totalFrames"]
            self.frames_done = event["frameIndex"] + 1
            self.video_time_sec = event["timeSec"]
            self.current_detected = event["detected"]
            self.current_confidence = event["confidence"]
            if event["analysed"]:
                self.frames_analysed += 1
                if event["detected"]:
                    self.frames_with_polyp += 1

    def latest(self) -> tuple[int, bytes]:
        with self._lock:
            return self.seq, self.jpeg

    def finish(self, result: Any) -> None:
        with self._lock:
            self.result = result
            self.state = "done"
            self.finished_at = time.monotonic()

    def fail(self, message: str, status_code: int) -> None:
        with self._lock:
            self.error = message
            self.error_status = status_code
            self.state = "error"
            self.finished_at = time.monotonic()

    @property
    def finished(self) -> bool:
        return self.state != "running"

    def status(self) -> dict:
        with self._lock:
            elapsed = (self.finished_at if self.finished_at is not None else time.monotonic()) - self.created_at
            # Video seconds played per wall-clock second, from the first to the latest released frame
            # (start-up and model warm-up excluded). About 1.0 keeps up with real time; below 1.0 the
            # playback runs slower than the original video.
            speed = 0.0
            if self.first_frame_at is not None and self.frames_done > 1:
                played = self.last_frame_at - self.first_frame_at
                speed = self.video_time_sec / played if played > 0 else 0.0
            return {
                "jobId": self.job_id,
                "state": self.state,
                "modelType": self.model_type,
                "originalFileName": self.file_name,
                "requestedSampleFps": self.requested_sample_fps,
                "sourceFps": round(self.source_fps, 3),
                "totalFrames": self.total_frames,
                "framesDone": self.frames_done,
                "framesAnalysed": self.frames_analysed,
                "framesWithPolyp": self.frames_with_polyp,
                "videoTimeSec": round(self.video_time_sec, 3),
                "durationSec": round(self.total_frames / self.source_fps, 3) if self.source_fps else 0.0,
                "elapsedSec": round(elapsed, 3),
                "realtimeFactor": round(min(speed, 9.99), 3),
                "currentDetected": self.current_detected,
                "currentConfidence": round(self.current_confidence, 4),
                "error": self.error,
            }


class LiveJobRegistry:
    def __init__(self) -> None:
        self._jobs: dict[str, LiveJob] = {}
        self._lock = threading.Lock()

    def create(self, model_type: str, file_name: str, sample_fps: int) -> LiveJob:
        with self._lock:
            self._evict()
            if len(self._jobs) >= MAX_JOBS:
                raise RuntimeError("Too many live video jobs are kept; finish or collect older ones first")
            job = LiveJob(uuid.uuid4().hex, model_type, file_name, sample_fps)
            self._jobs[job.job_id] = job
            return job

    def get(self, job_id: str) -> LiveJob | None:
        with self._lock:
            return self._jobs.get(job_id)

    def _evict(self) -> None:
        now = time.monotonic()
        for job_id, job in list(self._jobs.items()):
            if job.finished_at is not None and now - job.finished_at > FINISHED_JOB_TTL_SEC:
                del self._jobs[job_id]

    def clear(self) -> None:
        with self._lock:
            self._jobs.clear()


class ResultVideoStore:
    """Overlay videos waiting to be downloaded once (resultVideoTransfer=file).

    Keeps at most ``max_items`` videos for ``ttl_sec`` seconds; the oldest is dropped first so a client
    that never downloads cannot fill the memory."""

    def __init__(self, max_items: int = 4, ttl_sec: float = 1800.0) -> None:
        self._items: dict[str, tuple[float, bytes, str]] = {}
        self._lock = threading.Lock()
        self.max_items = max_items
        self.ttl_sec = ttl_sec

    def put(self, content: bytes, mime: str) -> str:
        video_id = uuid.uuid4().hex
        with self._lock:
            self._evict()
            while len(self._items) >= self.max_items:
                oldest = min(self._items, key=lambda key: self._items[key][0])
                del self._items[oldest]
            self._items[video_id] = (time.monotonic(), content, mime)
        return video_id

    def pop(self, video_id: str) -> tuple[bytes, str] | None:
        with self._lock:
            self._evict()
            item = self._items.pop(video_id, None)
        return None if item is None else (item[1], item[2])

    def _evict(self) -> None:
        cutoff = time.monotonic() - self.ttl_sec
        for key in [key for key, item in self._items.items() if item[0] < cutoff]:
            del self._items[key]

    def clear(self) -> None:
        with self._lock:
            self._items.clear()
