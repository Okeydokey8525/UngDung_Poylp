from __future__ import annotations

import asyncio
import base64
import struct
import threading
import time
import zlib
from io import BytesIO
from pathlib import Path
from typing import Any

import pytest
from fastapi.testclient import TestClient
from PIL import Image

import main


def image_bytes(format_name: str = "JPEG", size: tuple[int, int] = (13, 7)) -> bytes:
    output = BytesIO()
    Image.new("RGB", size, (24, 96, 144)).save(output, format=format_name)
    return output.getvalue()


JPEG_BYTES = image_bytes()
PNG_BYTES = image_bytes("PNG")
OVERLAY_BASE64 = base64.b64encode(JPEG_BYTES).decode("ascii")


def oversized_pixel_png_bytes() -> bytes:
    payload = struct.pack(">IIBBBBB", 8000, 6000, 8, 2, 0, 0, 0)
    chunk = b"IHDR" + payload
    return (
        b"\x89PNG\r\n\x1a\n"
        + struct.pack(">I", len(payload))
        + chunk
        + struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)
    )


class FakeModel:
    def __init__(self, key: str) -> None:
        self.key = key


class InferenceHarness:
    def __init__(self) -> None:
        self.call_order: list[str] = []
        self.active = 0
        self.max_active = 0
        self.delay = 0.0
        self.failures_remaining = 0
        self.failure_message = "private C:\\checkpoint\\secret.pt"
        self.started = threading.Event()
        self._guard = threading.Lock()
        self.overrides: dict[str, dict[str, Any]] = {}
        self.last_ground_truth = None

    def __call__(self, model: FakeModel, device: str, decoded: Image.Image, ground_truth=None):
        self.last_ground_truth = ground_truth
        with self._guard:
            self.call_order.append(model.key)
            self.active += 1
            self.max_active = max(self.max_active, self.active)
            should_fail = self.failures_remaining > 0
            if should_fail:
                self.failures_remaining -= 1
            self.started.set()
        try:
            if self.delay:
                time.sleep(self.delay)
            if should_fail:
                raise RuntimeError(self.failure_message)
            prediction = {
                "detected": True,
                "label": "polyp",
                "confidence": 0.934,
                "processingTimeMs": 12.5,
                "maskCount": 1,
                "resultImageBase64": OVERLAY_BASE64,
            }
            prediction.update(self.overrides.get(model.key, {}))
            return prediction
        finally:
            with self._guard:
                self.active -= 1


@pytest.fixture
def app_client(monkeypatch):
    def fake_load(model_name: str, config: main.ModelConfig, device: str):
        return main.ModelRuntime(
            config=config,
            model=FakeModel(model_name),
            lock=asyncio.Lock(),
            status="ready",
            checkpoint_sha256="FAKE-SHA256",
        )

    monkeypatch.setattr(main, "load_model_runtime", fake_load)
    harness = InferenceHarness()
    with TestClient(main.app) as client:
        main.app.state.mobile_run_inference = harness
        monkeypatch.setattr(main, "run_inference", harness)
        yield client, harness


def upload(
    content: bytes = JPEG_BYTES,
    *,
    filename: str = "sample.jpg",
    content_type: str = "image/jpeg",
):
    return {"image": (filename, content, content_type)}


def set_unavailable(key: str, error: str = "C:\\private\\checkpoint.pt") -> None:
    runtime = main.app.state.models[key]
    runtime.status = "error"
    runtime.model = None
    runtime.error = error
