"""Offline video analysis: sample frames, run a per-frame predictor, write an overlay video.

The predictor is injected so this module stays independent of Ultralytics and can be tested
with synthetic videos. Output is H.264 MP4 when the platform encoder is available (Windows Media
Foundation, about 3 ms per frame) and WebM/VP8 otherwise (about 33 ms per frame on the same laptop).
Both play in current browsers without extra codecs.

The output video keeps every source frame at the source frame rate, so playback is as smooth as the
original. Only sampled frames go through the model; each frame in between is drawn with the mask of
the most recent analysed frame (FramePrediction.render). ``sample_fps=0`` analyses every frame.
"""
from __future__ import annotations

import math
import os
import tempfile
import time
from dataclasses import dataclass, field
from time import perf_counter
from typing import Callable

import cv2
import numpy as np
from PIL import Image

OUTPUT_MAX_WIDTH = 854
# (fourcc, suffix, MIME type, OpenCV backend or None for the default). Tried in order.
OUTPUT_FORMATS = {
    "mp4": ("avc1", ".mp4", "video/mp4", getattr(cv2, "CAP_MSMF", None)),
    "webm": ("VP80", ".webm", "video/webm", None),
}
OUTPUT_ORDER = {
    "auto": ("mp4", "webm"),
    "mp4": ("mp4",),
    "webm": ("webm",),
}.get(os.getenv("AI_VIDEO_OUTPUT", "auto").strip().lower(), ("mp4", "webm"))


class VideoProcessingError(ValueError):
    """The uploaded video cannot be analysed (unreadable, too long, no frames)."""


ALL_FRAMES = 0


@dataclass
class FramePrediction:
    detected: bool
    confidence: float
    mask_count: int
    overlay_bgr: np.ndarray
    inference_ms: float
    # Draws this prediction's masks and outlines on another BGR frame of the same size. When it is
    # missing, frames between two samples repeat the last overlay.
    render: Callable[[np.ndarray], np.ndarray] | None = None


@dataclass
class VideoAnalysis:
    source_fps: float
    source_frame_count: int
    duration_sec: float
    width: int
    height: int
    sample_fps: float
    requested_sample_fps: float = 0.0
    sample_rate_reduced: bool = False
    output_fps: float = 0.0
    frames_written: int = 0
    frames_held: int = 0
    frames_processed: int = 0
    frames_with_polyp: int = 0
    max_confidence: float = 0.0
    processing_time_ms: float = 0.0
    inference_time_ms: float = 0.0
    timeline: list[dict] = field(default_factory=list)
    segments: list[dict] = field(default_factory=list)
    video_bytes: bytes = b""
    video_mime_type: str = "video/webm"


def _output_size(width: int, height: int) -> tuple[int, int]:
    scale = min(1.0, OUTPUT_MAX_WIDTH / width)
    out_w = max(2, int(round(width * scale)) // 2 * 2)
    out_h = max(2, int(round(height * scale)) // 2 * 2)
    return out_w, out_h


def _open_writer(fps: float, out_size: tuple[int, int]) -> tuple[cv2.VideoWriter, str, str]:
    """Open the first output format the platform can encode; returns (writer, temp path, MIME type)."""
    for key in OUTPUT_ORDER:
        fourcc, suffix, mime, backend = OUTPUT_FORMATS[key]
        if key == "mp4" and backend is None:
            continue
        handle, path = tempfile.mkstemp(suffix=suffix)
        os.close(handle)
        code = cv2.VideoWriter_fourcc(*fourcc)
        writer = (cv2.VideoWriter(path, backend, code, fps, out_size) if backend is not None
                  else cv2.VideoWriter(path, code, fps, out_size))
        if writer.isOpened():
            return writer, path, mime
        writer.release()
        os.remove(path)
    raise RuntimeError("OpenCV cannot open an MP4 (H.264) or WebM (VP8) writer")


def _fit(image_bgr: np.ndarray, out_size: tuple[int, int]) -> np.ndarray:
    if image_bgr.shape[1::-1] != out_size:
        image_bgr = cv2.resize(image_bgr, out_size, interpolation=cv2.INTER_AREA)
    return np.ascontiguousarray(image_bgr)


def _segments(timeline: list[dict], step_sec: float) -> list[dict]:
    """Merge consecutive positive samples into time ranges [startSec, endSec]."""
    segments: list[dict] = []
    current: dict | None = None
    for point in timeline:
        if point["detected"]:
            if current is None:
                current = {"startSec": point["timeSec"], "endSec": point["timeSec"],
                           "frames": 0, "maxConfidence": 0.0}
                segments.append(current)
            current["endSec"] = round(point["timeSec"] + step_sec, 3)
            current["frames"] += 1
            current["maxConfidence"] = max(current["maxConfidence"], point["confidence"])
        else:
            current = None
    return segments


def process_video(
    video_path: str,
    sample_fps: float,
    max_duration_sec: float,
    predict: Callable[[Image.Image], FramePrediction],
    max_frames: int = 1500,
    on_frame: Callable[[np.ndarray, dict], None] | None = None,
    realtime: bool = False,
) -> VideoAnalysis:
    """Analyse sampled frames and write every source frame to the overlay video.

    ``sample_fps=0`` (ALL_FRAMES) analyses every frame. When duration x sample_fps would exceed
    max_frames, the sampling rate is lowered so that the whole video is still covered, and the result
    is flagged as reduced.

    ``on_frame(frame_bgr, event)`` receives every frame written to the overlay video (used by the live
    view). With ``realtime=True`` frames are released no faster than the source frame rate, so a fast
    GPU plays the video at its original speed instead of fast-forwarding; a slow machine simply falls
    behind real time."""
    capture = cv2.VideoCapture(video_path)
    if not capture.isOpened():
        raise VideoProcessingError("Không đọc được tệp video.")
    output_path = None
    writer = None
    try:
        source_fps = capture.get(cv2.CAP_PROP_FPS)
        if not math.isfinite(source_fps) or source_fps <= 0 or source_fps > 240:
            source_fps = 25.0
        frame_count = int(capture.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH) or 0)
        height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT) or 0)
        if frame_count > 0 and frame_count / source_fps > max_duration_sec + 0.5:
            raise VideoProcessingError(
                f"Video dài {frame_count / source_fps:.1f} giây, vượt giới hạn {max_duration_sec:.0f} giây."
            )

        requested = float(sample_fps)
        effective_fps = source_fps if requested == ALL_FRAMES else min(requested, source_fps)
        reduced = False
        if frame_count > 0:
            duration = frame_count / source_fps
            if duration * effective_fps > max_frames:
                effective_fps = max_frames / duration
                reduced = True
        step = source_fps / effective_fps
        analysis = VideoAnalysis(
            source_fps=round(source_fps, 3),
            source_frame_count=frame_count,
            duration_sec=round(frame_count / source_fps, 3) if frame_count else 0.0,
            width=width,
            height=height,
            sample_fps=round(effective_fps, 3),
            requested_sample_fps=requested,
            sample_rate_reduced=reduced,
            output_fps=round(source_fps, 3),
        )

        started = perf_counter()
        frame_index = -1
        next_sample = 0.0
        last: FramePrediction | None = None
        pace_origin: list[float] = []  # wall-clock time of frame 0, fixed when the first frame is released

        def emit(frame_out: np.ndarray, analysed: bool) -> None:
            if realtime:
                # The clock starts at the first released frame, so writer start-up and model warm-up do
                # not make the first frames "late" and burst out at once.
                if not pace_origin:
                    pace_origin.append(perf_counter() - frame_index / source_fps)
                delay = pace_origin[0] + frame_index / source_fps - perf_counter()
                if delay > 0:
                    time.sleep(delay)
            if on_frame is not None:
                on_frame(frame_out, {
                    "frameIndex": frame_index,
                    "timeSec": frame_index / source_fps,
                    "sourceFps": source_fps,
                    "totalFrames": frame_count,
                    "analysed": analysed,
                    "detected": bool(last.detected) if last is not None else False,
                    "confidence": float(last.confidence) if last is not None and last.detected else 0.0,
                })
        while True:
            ok, frame_bgr = capture.read()
            if not ok:
                break
            frame_index += 1
            if frame_index / source_fps > max_duration_sec + 0.5:
                raise VideoProcessingError(f"Video vượt giới hạn {max_duration_sec:.0f} giây.")

            if writer is None:
                height, width = frame_bgr.shape[:2]
                analysis.width, analysis.height = width, height
                out_size = _output_size(width, height)
                writer, output_path, analysis.video_mime_type = _open_writer(source_fps, out_size)

            if frame_index + 1e-6 < next_sample and last is not None:
                # Between two samples: keep the real source frame and draw the latest mask on it.
                held = _fit(last.render(frame_bgr) if last.render is not None else last.overlay_bgr, out_size)
                writer.write(held)
                analysis.frames_written += 1
                analysis.frames_held += 1
                emit(held, analysed=False)
                continue
            next_sample += step
            if analysis.frames_processed >= max_frames:
                raise VideoProcessingError(
                    f"Video cần phân tích hơn {max_frames} khung; hãy cắt ngắn hoặc giảm số khung/giây."
                )

            frame_rgb = Image.fromarray(np.ascontiguousarray(frame_bgr[..., ::-1]))
            prediction = predict(frame_rgb)
            last = prediction
            written = _fit(prediction.overlay_bgr, out_size)
            writer.write(written)
            analysis.frames_written += 1
            emit(written, analysed=True)

            confidence = float(prediction.confidence) if prediction.detected else 0.0
            analysis.frames_processed += 1
            analysis.inference_time_ms += prediction.inference_ms
            if prediction.detected:
                analysis.frames_with_polyp += 1
                analysis.max_confidence = max(analysis.max_confidence, confidence)
            analysis.timeline.append({
                "frameIndex": frame_index,
                "timeSec": round(frame_index / source_fps, 3),
                "detected": bool(prediction.detected),
                "confidence": round(confidence, 4),
                "maskCount": int(prediction.mask_count),
            })

        if analysis.frames_processed == 0:
            raise VideoProcessingError("Video không có khung hình đọc được.")
        if not analysis.source_frame_count:
            analysis.source_frame_count = frame_index + 1
            analysis.duration_sec = round((frame_index + 1) / source_fps, 3)
        analysis.processing_time_ms = (perf_counter() - started) * 1000
        writer.release()
        writer = None
        with open(output_path, "rb") as output:
            analysis.video_bytes = output.read()
        if not analysis.video_bytes:
            raise RuntimeError("OpenCV wrote an empty overlay video")
        analysis.segments = _segments(analysis.timeline, 1.0 / effective_fps)
        return analysis
    finally:
        capture.release()
        if writer is not None:
            writer.release()
        if output_path and os.path.exists(output_path):
            os.remove(output_path)
