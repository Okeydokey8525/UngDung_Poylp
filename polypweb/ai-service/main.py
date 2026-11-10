from __future__ import annotations

import asyncio
import base64
import hashlib
import importlib.util
import logging
import math
import os
import re
import sys
import tempfile
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from time import perf_counter
from typing import Any

import cv2
import numpy as np
import torch
from fastapi import FastAPI, File, Form, HTTPException, Request, Response, UploadFile, status
from fastapi.exception_handlers import (
    http_exception_handler,
    request_validation_exception_handler,
)
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, StreamingResponse
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel

from mobile_contract import MobileErrorResponse
from mobile_routes import MobileApiError, create_mobile_router
from video_processing import ALL_FRAMES, FramePrediction, VideoProcessingError, process_video
from live_video import LiveJob, LiveJobRegistry, ResultVideoStore
from ground_truth import binarize_ground_truth, draw_ground_truth, pixel_metrics, predicted_mask

PIL_IMAGE_OPEN = Image.open

BASE_DIR = Path(__file__).resolve().parent
VMAMBA_MODULE_PATH = BASE_DIR / "custom_ultralytics" / "topology_shape_vmamba.py"
CONTOUR_COLOR_BGR = (0, 255, 255)  # yellow outline, visible on both the mask fill and the mucosa


def register_vmamba_module() -> None:
    """Register the exact TSVM classes referenced by the FP32 experiment checkpoint."""
    import ultralytics.nn.modules as modules_package
    import ultralytics.nn.tasks as tasks_package

    module_name = "ultralytics.nn.modules.topology_shape_vmamba"
    if module_name in sys.modules:
        tsvm_module = sys.modules[module_name]
    else:
        if not VMAMBA_MODULE_PATH.is_file():
            raise RuntimeError(f"TSVM module was not found: {VMAMBA_MODULE_PATH}")
        spec = importlib.util.spec_from_file_location(module_name, VMAMBA_MODULE_PATH)
        if spec is None or spec.loader is None:
            raise RuntimeError("Could not create the TSVM module specification")
        tsvm_module = importlib.util.module_from_spec(spec)
        sys.modules[module_name] = tsvm_module
        try:
            spec.loader.exec_module(tsvm_module)
        except Exception:
            sys.modules.pop(module_name, None)
            raise
    setattr(modules_package, "topology_shape_vmamba", tsvm_module)
    for name in ("C2TSVMamba", "TSVMamba", "SS2D", "ShapeAwareBranch",
                 "DirectionalShapeExtractor", "TopologyShapeGate"):
        setattr(modules_package, name, getattr(tsvm_module, name))
        setattr(tasks_package, name, getattr(tsvm_module, name))


VMAMBA_MODULE_ERROR: str | None = None
try:
    register_vmamba_module()
except Exception as exception:
    VMAMBA_MODULE_ERROR = f"{type(exception).__name__}: {exception}"

from ultralytics import YOLO

LOGGER = logging.getLogger("uvicorn.error")
DEVICE_SETTING = os.getenv("AI_DEVICE", "auto").strip().lower()
CONFIDENCE_THRESHOLD = float(os.getenv("AI_CONFIDENCE_THRESHOLD", "0.25"))
INFERENCE_IMAGE_SIZE = int(os.getenv("AI_IMAGE_SIZE", "640"))
MAX_FILE_SIZE = 10 * 1024 * 1024
MAX_IMAGE_PIXELS = 40_000_000
ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png"}
ALLOWED_IMAGE_FORMATS = {"JPEG", "PNG"}
REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$")
# 0 = analyse every frame (GPU only); otherwise frames analysed per second of video.
VIDEO_SAMPLE_FPS_CHOICES = {ALL_FRAMES, 2, 5, 10}
ALLOWED_VIDEO_EXTENSIONS = {".mp4", ".avi", ".mov", ".mkv", ".webm"}


def positive_int_setting(name: str, default: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
        return value if value >= 1 else default
    except (TypeError, ValueError):
        return default


def positive_float_setting(name: str, default: float) -> float:
    try:
        value = float(os.getenv(name, str(default)))
        return value if math.isfinite(value) and value > 0 else default
    except (TypeError, ValueError):
        return default


MAX_CONCURRENT_MOBILE_INFERENCE = positive_int_setting(
    "AI_MAX_CONCURRENT_INFERENCE", 1
)
MOBILE_QUEUE_TIMEOUT_SECONDS = positive_float_setting(
    "AI_INFERENCE_QUEUE_TIMEOUT_SECONDS", 5.0
)
MOBILE_INFERENCE_TIMEOUT_SECONDS = positive_float_setting(
    "AI_INFERENCE_TIMEOUT_SECONDS", 120.0
)
# Offline video limits (web only). Longer videos should be cut into parts before upload.
MAX_VIDEO_FILE_MB = positive_int_setting("AI_VIDEO_MAX_MB", 200)
MAX_VIDEO_FILE_SIZE = MAX_VIDEO_FILE_MB * 1024 * 1024
MAX_VIDEO_SECONDS = positive_float_setting("AI_VIDEO_MAX_SECONDS", 300.0)
# Enough for every frame of a 5-minute 30 FPS video; sampled modes stay far below it.
MAX_VIDEO_FRAMES = positive_int_setting("AI_VIDEO_MAX_FRAMES", 9000)
VIDEO_UPLOAD_CHUNK = 1024 * 1024

Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS


@dataclass(frozen=True)
class ModelConfig:
    path: Path
    family: str
    enabled: bool = True


@dataclass
class ModelRuntime:
    config: ModelConfig
    model: YOLO | None
    lock: asyncio.Lock
    status: str
    error: str | None = None
    checkpoint_sha256: str | None = None


MODEL_CONFIG: dict[str, ModelConfig] = {
    "YOLO26s-seg": ModelConfig(
        path=Path(
            os.getenv(
                "AI_BASELINE_MODEL_PATH",
                os.getenv(
                    "AI_MODEL_PATH",
                    str(BASE_DIR / "models" / "yolo26s-seg-best.pt"),
                ),
            )
        )
        .expanduser()
        .resolve(),
        family="baseline",
    ),
    "YOLO26s-TSVM-FP32-seg": ModelConfig(
        path=Path(
            os.getenv(
                "AI_VMAMBA_MODEL_PATH",
                str(BASE_DIR / "models" / "yolo26s-tsvm-fp32-best.pt"),
            )
        )
        .expanduser()
        .resolve(),
        family="vmamba",
    ),
}


class GroundTruthMetrics(BaseModel):
    dice: float | None
    iou: float | None
    precision: float | None
    recall: float | None
    truePositivePixels: int
    falsePositivePixels: int
    falseNegativePixels: int
    groundTruthPixels: int
    predictedPixels: int
    imagePixels: int
    backgroundImage: bool


class PredictionResponse(BaseModel):
    success: bool
    detected: bool
    label: str | None
    confidence: float
    processingTimeMs: float
    maskCount: int
    modelType: str
    originalFileName: str
    resultImageBase64: str
    message: str
    groundTruthMetrics: GroundTruthMetrics | None = None


def resolve_device() -> str:
    if DEVICE_SETTING == "auto":
        return "cuda:0" if torch.cuda.is_available() else "cpu"
    if DEVICE_SETTING.startswith("cuda") and not torch.cuda.is_available():
        raise RuntimeError(
            f"AI_DEVICE={DEVICE_SETTING} was requested but CUDA is not available"
        )
    return DEVICE_SETTING


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as checkpoint:
        for chunk in iter(lambda: checkpoint.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def load_model_runtime(
    model_name: str,
    config: ModelConfig,
    device: str,
) -> ModelRuntime:
    runtime = ModelRuntime(
        config=config,
        model=None,
        lock=asyncio.Lock(),
        status="loading",
    )
    if not config.enabled:
        runtime.status = "disabled"
        return runtime

    try:
        if not config.path.is_file():
            raise FileNotFoundError(f"checkpoint not found: {config.path.name}")
        if config.family == "vmamba" and VMAMBA_MODULE_ERROR is not None:
            raise RuntimeError(
                f"custom VMamba module could not be registered: {VMAMBA_MODULE_ERROR}"
            )

        LOGGER.info("Loading %s from %s", model_name, config.path)
        model = YOLO(str(config.path), task="segment")
        if model.task != "segment":
            raise RuntimeError(f"checkpoint task is {model.task!r}, expected 'segment'")
        if "polyp" not in {str(name).casefold() for name in model.names.values()}:
            raise RuntimeError("checkpoint class names do not contain 'polyp'")

        model.to(device)
        model.model.float()  # Preserve FP32 for the TSVM state-space and BatchNorm path.
        if config.family == "vmamba" and not any(
            type(layer).__name__ == "C2TSVMamba" for layer in model.model.modules()
        ):
            raise RuntimeError("research checkpoint does not contain C2TSVMamba")
        runtime.model = model
        runtime.checkpoint_sha256 = file_sha256(config.path)
        runtime.status = "ready"
        LOGGER.info("%s loaded successfully on %s", model_name, device)
    except Exception as exception:
        runtime.status = "error"
        runtime.error = f"{type(exception).__name__}: {exception}"
        LOGGER.exception("%s failed to load", model_name)

    return runtime


@asynccontextmanager
async def lifespan(app: FastAPI):
    device = resolve_device()
    app.state.device = device
    app.state.models = {
        model_name: load_model_runtime(model_name, config, device)
        for model_name, config in MODEL_CONFIG.items()
    }
    app.state.mobile_inference_semaphore = asyncio.Semaphore(
        MAX_CONCURRENT_MOBILE_INFERENCE
    )
    app.state.mobile_queue_timeout_seconds = MOBILE_QUEUE_TIMEOUT_SECONDS
    app.state.mobile_inference_timeout_seconds = MOBILE_INFERENCE_TIMEOUT_SECONDS
    app.state.mobile_run_inference = run_inference
    ready_count = sum(
        runtime.status == "ready" for runtime in app.state.models.values()
    )
    LOGGER.info(
        "Model registry initialized: %s/%s models ready",
        ready_count,
        len(app.state.models),
    )

    yield

    for runtime in app.state.models.values():
        runtime.model = None
    app.state.models = {}
    if torch.cuda.is_available():
        torch.cuda.empty_cache()


app = FastAPI(
    title="PolypVision AI API",
    description="YOLO26s-seg and Topology-Shape-aware VMamba FP32 segmentation service.",
    version="0.3.0",
    lifespan=lifespan,
)


def mobile_request_id(request: Request) -> str:
    value = request.headers.get("X-Request-ID", "").strip()
    return value if REQUEST_ID_PATTERN.fullmatch(value) else str(uuid.uuid4())


def mobile_error_response(
    request: Request,
    status_code: int,
    code: str,
    message: str,
    field_errors: dict[str, str] | None = None,
) -> JSONResponse:
    body = MobileErrorResponse(
        requestId=request.state.request_id,
        status=status_code,
        code=code,
        message=message,
        fieldErrors=field_errors or {},
    )
    return JSONResponse(
        status_code=status_code,
        content=body.model_dump(),
        headers={"Cache-Control": "no-store"},
    )


@app.middleware("http")
async def mobile_request_context(request: Request, call_next):
    if not request.url.path.startswith("/api/v1/"):
        return await call_next(request)

    request.state.request_id = mobile_request_id(request)
    started = perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        LOGGER.error(
            "Mobile API internal error requestId=%s method=%s path=%s",
            request.state.request_id,
            request.method,
            request.url.path,
        )
        response = mobile_error_response(
            request,
            500,
            "INTERNAL_ERROR",
            "Đã xảy ra lỗi nội bộ. Vui lòng thử lại sau.",
        )
    duration_ms = (perf_counter() - started) * 1000
    response.headers["X-Request-ID"] = request.state.request_id
    LOGGER.info(
        "Mobile API requestId=%s method=%s path=%s status=%s durationMs=%.3f",
        request.state.request_id,
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


@app.exception_handler(MobileApiError)
async def mobile_api_error_handler(
    request: Request, exception: MobileApiError
) -> JSONResponse:
    return mobile_error_response(
        request,
        exception.status_code,
        exception.code,
        exception.message,
        exception.field_errors,
    )


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exception: RequestValidationError):
    if not request.url.path.startswith("/api/v1/"):
        return await request_validation_exception_handler(request, exception)
    field_errors: dict[str, str] = {}
    for error in exception.errors():
        location = error.get("loc", ())
        field = str(location[-1]) if location else "request"
        field_errors.setdefault(field, str(error.get("msg", "Dữ liệu không hợp lệ.")))
    return mobile_error_response(
        request,
        422,
        "VALIDATION_ERROR",
        "Dữ liệu yêu cầu không hợp lệ.",
        field_errors,
    )


@app.exception_handler(HTTPException)
async def http_error_handler(request: Request, exception: HTTPException):
    if not request.url.path.startswith("/api/v1/"):
        return await http_exception_handler(request, exception)
    code = {
        413: "FILE_TOO_LARGE",
        415: "UNSUPPORTED_MEDIA_TYPE",
        422: "INVALID_IMAGE",
        503: "MODEL_NOT_READY",
    }.get(exception.status_code, "INTERNAL_ERROR")
    message = exception.detail if isinstance(exception.detail, str) else "Yêu cầu không hợp lệ."
    return mobile_error_response(request, exception.status_code, code, message)


@app.get("/health")
async def health(request: Request) -> dict[str, Any]:
    models = {
        model_name: {
            "status": runtime.status,
            "loaded": runtime.model is not None,
            "family": runtime.config.family,
            "checkpoint": runtime.config.path.name,
            "checkpointSha256": runtime.checkpoint_sha256,
            "error": runtime.error,
        }
        for model_name, runtime in request.app.state.models.items()
    }
    ready_count = sum(item["loaded"] for item in models.values())
    return {
        "status": "ok" if ready_count == len(models) else "degraded",
        "service": "polypvision-ai",
        "device": request.app.state.device,
        "readyModels": ready_count,
        "totalModels": len(models),
        "models": models,
    }


def decode_image(content: bytes, declared_content_type: str) -> Image.Image:
    try:
        with PIL_IMAGE_OPEN(BytesIO(content)) as source:
            width, height = source.size
            if width <= 0 or height <= 0 or width * height > MAX_IMAGE_PIXELS:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail="The decoded image exceeds 40 million pixels",
                )
            source.verify()
            image_format = source.format

        if image_format not in ALLOWED_IMAGE_FORMATS:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="The decoded file is not a JPG, JPEG or PNG image",
            )

        expected_format = "JPEG" if declared_content_type == "image/jpeg" else "PNG"
        if image_format != expected_format:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="The declared MIME type does not match the decoded image format",
            )

        with PIL_IMAGE_OPEN(BytesIO(content)) as source:
            decoded = ImageOps.exif_transpose(source).convert("RGB")
            decoded.load()
            return decoded
    except HTTPException:
        raise
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="The uploaded file cannot be decoded as a valid image",
        ) from None


def draw_polyp_contours(image_bgr: np.ndarray, result: Any) -> np.ndarray:
    """Draw a closed outline around every predicted polyp mask on top of the plotted overlay."""
    masks = getattr(result, "masks", None)
    polygons = getattr(masks, "xy", None) if masks is not None else None
    if not polygons:
        return image_bgr

    outlined = np.ascontiguousarray(image_bgr)
    thickness = max(2, round(max(outlined.shape[:2]) / 300))
    for polygon in polygons:
        if polygon is None or len(polygon) < 3:
            continue
        points = np.round(np.asarray(polygon, dtype=np.float32)).astype(np.int32).reshape(-1, 1, 2)
        cv2.polylines(outlined, [points], isClosed=True, color=CONTOUR_COLOR_BGR,
                      thickness=thickness, lineType=cv2.LINE_AA)
    return outlined


def encode_result_image(result: Any, ground_truth: np.ndarray | None = None) -> str:
    plotted_bgr = result.plot()
    if plotted_bgr is None or plotted_bgr.size == 0:
        raise RuntimeError("The model produced an empty result image")

    plotted_bgr = draw_polyp_contours(plotted_bgr, result)
    if ground_truth is not None:
        plotted_bgr = draw_ground_truth(plotted_bgr, ground_truth)
    plotted_rgb = np.ascontiguousarray(plotted_bgr[..., ::-1])
    output = BytesIO()
    Image.fromarray(plotted_rgb).save(output, format="JPEG", quality=90)
    return base64.b64encode(output.getvalue()).decode("ascii")


def run_inference(
    model: YOLO,
    device: str,
    decoded_image: Image.Image,
    ground_truth: np.ndarray | None = None,
) -> dict[str, Any]:
    inference_started = perf_counter()
    results = model.predict(
        source=decoded_image,  # PIL preserves RGB; ndarray inputs are interpreted as BGR.
        conf=CONFIDENCE_THRESHOLD,
        imgsz=INFERENCE_IMAGE_SIZE,
        device=device,
        half=False,
        verbose=False,
        # Masks at the original resolution only when they are scored against a ground truth,
        # matching the thesis pixel protocol; plain requests keep the measured latency path.
        retina_masks=ground_truth is not None,
    )
    inference_time_ms = (perf_counter() - inference_started) * 1000

    if not math.isfinite(inference_time_ms):
        raise RuntimeError("The model returned a non-finite processing time")
    if not results:
        raise RuntimeError("The model returned no result object")

    result = results[0]
    boxes = result.boxes
    masks = result.masks
    has_masks = masks is not None and masks.data is not None and len(masks.data) > 0
    has_boxes = boxes is not None and boxes.conf is not None and len(boxes.conf) > 0
    detected = bool(has_masks and has_boxes)
    mask_count = int(len(masks.data)) if has_masks else 0

    confidence = 0.0
    label: str | None = None
    if detected:
        confidences = boxes.conf.detach().cpu()
        if not bool(torch.isfinite(confidences).all()):
            raise RuntimeError("The model returned NaN or infinite confidence")
        best_index = int(torch.argmax(confidences).item())
        confidence = float(confidences[best_index].item())

        class_id = int(boxes.cls[best_index].item())
        names = result.names
        label = names.get(class_id, "polyp") if isinstance(names, dict) else names[class_id]

    metrics = None
    if ground_truth is not None:
        height, width = ground_truth.shape
        metrics = pixel_metrics(predicted_mask(result, height, width), ground_truth)

    render_started = perf_counter()
    result_image_base64 = encode_result_image(result, ground_truth)
    render_time_ms = (perf_counter() - render_started) * 1000

    return {
        "groundTruthMetrics": metrics,
        "detected": detected,
        "label": label,
        "confidence": confidence,
        "processingTimeMs": round(inference_time_ms, 3),
        "renderTimeMs": round(render_time_ms, 3),
        "maskCount": mask_count,
        "resultImageBase64": result_image_base64,
    }


def server_timing_header(stages: dict[str, float | None]) -> str:
    """Build a W3C Server-Timing header (durations in ms) without changing the JSON contract."""
    parts = []
    for name, duration in stages.items():
        if duration is not None and math.isfinite(duration):
            parts.append(f"{name};dur={duration:.3f}")
    return ", ".join(parts)


def find_runtime(request: Request, requested_model: str) -> tuple[str, ModelRuntime]:
    canonical_name = next(
        (
            model_name
            for model_name in MODEL_CONFIG
            if model_name.casefold() == requested_model.casefold()
        ),
        None,
    )
    if canonical_name is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Model is not available",
        )

    runtime = request.app.state.models[canonical_name]
    if runtime.status != "ready" or runtime.model is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"{canonical_name} is currently unavailable",
        )
    return canonical_name, runtime


@app.post("/predict", response_model=PredictionResponse, response_model_exclude_unset=True)
async def predict(
    request: Request,
    response: Response,
    image: UploadFile = File(...),
    modelType: str = Form(...),
    groundTruth: UploadFile | None = File(None),
) -> PredictionResponse:
    request_started = perf_counter()
    requested_model = modelType.strip()
    if not requested_model:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="modelType is required",
        )
    canonical_name, runtime = find_runtime(request, requested_model)

    if image.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only JPG, JPEG and PNG images are supported",
        )

    content = await image.read(MAX_FILE_SIZE + 1)
    await image.close()
    if not content:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="The uploaded image is empty",
        )
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="The uploaded image exceeds 10 MB",
        )

    decode_started = perf_counter()
    decoded_image = decode_image(content, image.content_type)
    decode_time_ms = (perf_counter() - decode_started) * 1000
    ground_truth = await read_ground_truth(groundTruth, decoded_image.size)
    try:
        async with runtime.lock:
            prediction = await asyncio.to_thread(
                run_inference,
                runtime.model,
                request.app.state.device,
                decoded_image,
                ground_truth,
            )
    except Exception:
        LOGGER.exception(
            "Inference failed for %s using %s",
            image.filename,
            canonical_name,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"{canonical_name} could not process this image",
        ) from None

    detected = prediction["detected"]
    response.headers["Server-Timing"] = server_timing_header(
        {
            "decode": decode_time_ms,
            "infer": prediction.get("processingTimeMs"),
            "render": prediction.get("renderTimeMs"),
            "total": (perf_counter() - request_started) * 1000,
        }
    )
    extra = {}
    if prediction.get("groundTruthMetrics") is not None:
        extra["groundTruthMetrics"] = prediction["groundTruthMetrics"]
    return PredictionResponse(
        **extra,
        success=True,
        detected=detected,
        label=prediction["label"],
        confidence=prediction["confidence"],
        processingTimeMs=prediction["processingTimeMs"],
        maskCount=prediction["maskCount"],
        modelType=canonical_name,
        originalFileName=Path(image.filename or "uploaded-image.jpg").name,
        resultImageBase64=prediction["resultImageBase64"],
        message=(
            "Inference completed"
            if detected
            else "No suspected polyp region detected"
        ),
    )


async def read_ground_truth(
    upload: UploadFile | None,
    image_size: tuple[int, int],
) -> np.ndarray | None:
    """Decode the optional ground-truth mask (JPG/PNG, same width x height as the image)."""
    if upload is None or not (upload.filename or "").strip():
        return None
    if upload.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="The ground-truth mask must be a JPG, JPEG or PNG image",
        )
    content = await upload.read(MAX_FILE_SIZE + 1)
    await upload.close()
    if not content:
        return None
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="The ground-truth mask exceeds 10 MB",
        )
    mask_image = decode_image(content, upload.content_type)
    if mask_image.size != image_size:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"The ground-truth mask is {mask_image.size[0]}x{mask_image.size[1]} "
                f"but the image is {image_size[0]}x{image_size[1]}"
            ),
        )
    return binarize_ground_truth(mask_image)


class VideoTimelinePoint(BaseModel):
    frameIndex: int
    timeSec: float
    detected: bool
    confidence: float
    maskCount: int


class VideoSegment(BaseModel):
    startSec: float
    endSec: float
    frames: int
    maxConfidence: float


class VideoPredictionResponse(BaseModel):
    success: bool
    modelType: str
    originalFileName: str
    sourceFps: float
    sourceFrameCount: int
    durationSec: float
    width: int
    height: int
    sampleFps: float
    requestedSampleFps: float
    sampleRateReduced: bool
    outputFps: float
    framesWritten: int
    framesHeld: int
    framesProcessed: int
    framesWithPolyp: int
    maxConfidence: float
    processingTimeMs: float
    averageInferenceMs: float
    throughputFps: float
    timeline: list[VideoTimelinePoint]
    segments: list[VideoSegment]
    # Inline transfer (default): the overlay video as Base64. File transfer: empty, and the video is
    # downloaded once from GET /video/result/{resultVideoId} (needed for long all-frame videos, whose
    # Base64 can exceed what a JSON client accepts).
    resultVideoBase64: str
    resultVideoMimeType: str
    resultVideoId: str | None = None
    resultVideoBytes: int = 0
    message: str


def predict_video_frame(model: YOLO, device: str, frame: Image.Image) -> FramePrediction:
    """Run one sampled video frame with the same settings as single-image inference.

    ``half`` is left at its float32 default: passing ``half=False`` explicitly makes Ultralytics print a
    deprecation warning for every frame, which floods the log for long videos.
    """
    started = perf_counter()
    results = model.predict(
        source=frame,
        conf=CONFIDENCE_THRESHOLD,
        imgsz=INFERENCE_IMAGE_SIZE,
        device=device,
        verbose=False,
    )
    inference_ms = (perf_counter() - started) * 1000
    if not results:
        raise RuntimeError("The model returned no result object")
    result = results[0]
    boxes = result.boxes
    masks = result.masks
    has_masks = masks is not None and masks.data is not None and len(masks.data) > 0
    has_boxes = boxes is not None and boxes.conf is not None and len(boxes.conf) > 0
    detected = bool(has_masks and has_boxes)
    confidence = 0.0
    if detected:
        confidences = boxes.conf.detach().cpu()
        if not bool(torch.isfinite(confidences).all()):
            raise RuntimeError("The model returned NaN or infinite confidence")
        confidence = float(confidences.max().item())
    overlay = draw_polyp_contours(result.plot(), result)

    def render(frame_bgr: np.ndarray) -> np.ndarray:
        """Draw this frame's masks, boxes and outlines on a later frame of the same video."""
        if not detected:
            return frame_bgr
        return draw_polyp_contours(result.plot(img=np.ascontiguousarray(frame_bgr)), result)

    return FramePrediction(
        detected=detected,
        confidence=confidence,
        mask_count=int(len(masks.data)) if has_masks else 0,
        overlay_bgr=overlay,
        inference_ms=inference_ms,
        render=render,
    )


def check_video_request(request: Request, model_type: str, sample_fps: int, video: UploadFile) -> tuple[str, Any, str, str]:
    """Shared validation for offline and live video analysis; returns (model, runtime, file name, extension)."""
    requested_model = model_type.strip()
    if not requested_model:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="modelType is required")
    canonical_name, runtime = find_runtime(request, requested_model)
    if sample_fps not in VIDEO_SAMPLE_FPS_CHOICES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"sampleFps must be one of {sorted(VIDEO_SAMPLE_FPS_CHOICES)}",
        )
    if sample_fps == ALL_FRAMES and not str(request.app.state.device).startswith("cuda"):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Analysing every frame needs the AI service to run on a GPU",
        )
    file_name = Path(video.filename or "uploaded-video.mp4").name
    extension = Path(file_name).suffix.lower()
    content_type = (video.content_type or "").lower()
    if extension not in ALLOWED_VIDEO_EXTENSIONS or not (
        content_type.startswith("video/") or content_type == "application/octet-stream"
    ):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Only MP4, AVI, MOV, MKV and WEBM videos are supported",
        )
    return canonical_name, runtime, file_name, extension


async def save_video_upload(video: UploadFile, extension: str) -> str:
    """Stream the upload to a temp file in chunks so a 200 MB video is never held in memory twice."""
    handle, source_path = tempfile.mkstemp(suffix=extension)
    try:
        written = 0
        with os.fdopen(handle, "wb") as source_file:
            while chunk := await video.read(VIDEO_UPLOAD_CHUNK):
                written += len(chunk)
                if written > MAX_VIDEO_FILE_SIZE:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail=f"The uploaded video exceeds {MAX_VIDEO_FILE_MB} MB",
                    )
                source_file.write(chunk)
        await video.close()
        if written == 0:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="The uploaded video is empty")
        return source_path
    except BaseException:
        if os.path.exists(source_path):
            os.remove(source_path)
        raise


VIDEO_TRANSFERS = {"inline", "file"}
RESULT_VIDEOS = ResultVideoStore()


def check_video_transfer(transfer: str) -> str:
    value = (transfer or "inline").strip().lower()
    if value not in VIDEO_TRANSFERS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"resultVideoTransfer must be one of {sorted(VIDEO_TRANSFERS)}",
        )
    return value


def video_response(
    analysis: Any, canonical_name: str, file_name: str, transfer: str = "inline"
) -> VideoPredictionResponse:
    seconds = analysis.processing_time_ms / 1000
    video_id = RESULT_VIDEOS.put(analysis.video_bytes, analysis.video_mime_type) if transfer == "file" else None
    return VideoPredictionResponse(
        success=True,
        modelType=canonical_name,
        originalFileName=file_name,
        sourceFps=analysis.source_fps,
        sourceFrameCount=analysis.source_frame_count,
        durationSec=analysis.duration_sec,
        width=analysis.width,
        height=analysis.height,
        sampleFps=analysis.sample_fps,
        requestedSampleFps=analysis.requested_sample_fps,
        sampleRateReduced=analysis.sample_rate_reduced,
        outputFps=analysis.output_fps,
        framesWritten=analysis.frames_written,
        framesHeld=analysis.frames_held,
        framesProcessed=analysis.frames_processed,
        framesWithPolyp=analysis.frames_with_polyp,
        maxConfidence=round(analysis.max_confidence, 4),
        processingTimeMs=round(analysis.processing_time_ms, 3),
        averageInferenceMs=round(analysis.inference_time_ms / analysis.frames_processed, 3),
        throughputFps=round(analysis.frames_processed / seconds, 3) if seconds > 0 else 0.0,
        timeline=analysis.timeline,
        segments=analysis.segments,
        resultVideoBase64="" if video_id else base64.b64encode(analysis.video_bytes).decode("ascii"),
        resultVideoMimeType=analysis.video_mime_type,
        resultVideoId=video_id,
        resultVideoBytes=len(analysis.video_bytes),
        message=(
            "Video inference completed"
            if analysis.frames_with_polyp
            else "No suspected polyp region detected in sampled frames"
        ),
    )


@app.post("/video/predict", response_model=VideoPredictionResponse)
async def predict_video(
    request: Request,
    video: UploadFile = File(...),
    modelType: str = Form(...),
    sampleFps: int = Form(5),
    resultVideoTransfer: str = Form("inline"),
) -> VideoPredictionResponse:
    """Offline video analysis for the web client: sampled frames, overlay video and a detection timeline."""
    transfer = check_video_transfer(resultVideoTransfer)
    canonical_name, runtime, file_name, extension = check_video_request(request, modelType, sampleFps, video)
    source_path = await save_video_upload(video, extension)
    try:
        device = request.app.state.device

        def predict_frame(frame: Image.Image) -> FramePrediction:
            return predict_video_frame(runtime.model, device, frame)

        try:
            async with runtime.lock:
                analysis = await asyncio.to_thread(
                    process_video, source_path, sampleFps, MAX_VIDEO_SECONDS, predict_frame, MAX_VIDEO_FRAMES
                )
        except VideoProcessingError as exception:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exception)
            ) from None
        except Exception:
            LOGGER.exception("Video inference failed for %s using %s", file_name, canonical_name)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"{canonical_name} could not process this video",
            ) from None
    finally:
        if os.path.exists(source_path):
            os.remove(source_path)
    return video_response(analysis, canonical_name, file_name, transfer)


@app.get("/video/result/{video_id}")
async def download_result_video(video_id: str) -> Response:
    """One-time download of an overlay video kept by resultVideoTransfer=file (removed once served)."""
    entry = RESULT_VIDEOS.pop(video_id) if re.fullmatch(r"[0-9a-f]{32}", video_id or "") else None
    if entry is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Result video not found or expired")
    content, mime = entry
    return Response(content=content, media_type=mime, headers={"Cache-Control": "no-store"})


# ----------------------------------------------------------------- real-time playback simulation
LIVE_JOBS = LiveJobRegistry()
LIVE_STREAM_BOUNDARY = "polypframe"
LIVE_STREAM_POLL_SEC = 0.01


class LiveVideoStart(BaseModel):
    jobId: str
    modelType: str
    originalFileName: str
    requestedSampleFps: int


async def run_live_job(job: LiveJob, runtime: Any, device: str, source_path: str, sample_fps: int) -> None:
    def predict_frame(frame: Image.Image) -> FramePrediction:
        return predict_video_frame(runtime.model, device, frame)

    try:
        async with runtime.lock:
            analysis = await asyncio.to_thread(
                process_video, source_path, sample_fps, MAX_VIDEO_SECONDS, predict_frame, MAX_VIDEO_FRAMES,
                job.push, True,
            )
        job.finish(analysis)
    except VideoProcessingError as exception:
        job.fail(str(exception), status.HTTP_422_UNPROCESSABLE_ENTITY)
    except Exception:
        LOGGER.exception("Live video job %s failed using %s", job.job_id, job.model_type)
        job.fail(f"{job.model_type} could not process this video", status.HTTP_500_INTERNAL_SERVER_ERROR)
    finally:
        if os.path.exists(source_path):
            os.remove(source_path)


def require_live_job(job_id: str) -> LiveJob:
    job = LIVE_JOBS.get(job_id) if re.fullmatch(r"[0-9a-f]{32}", job_id or "") else None
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Live video job not found")
    return job


@app.post("/video/live", response_model=LiveVideoStart, status_code=status.HTTP_202_ACCEPTED)
async def start_live_video(
    request: Request,
    video: UploadFile = File(...),
    modelType: str = Form(...),
    sampleFps: int = Form(5),
) -> LiveVideoStart:
    """Start a real-time playback simulation: frames are analysed and released at the source frame rate.

    Watch it with GET /video/live/{jobId}/stream, follow it with /status and collect the same payload as
    POST /video/predict from /result once the state is "done".
    """
    canonical_name, runtime, file_name, extension = check_video_request(request, modelType, sampleFps, video)
    source_path = await save_video_upload(video, extension)
    try:
        job = LIVE_JOBS.create(canonical_name, file_name, sampleFps)
    except RuntimeError as exception:
        os.remove(source_path)
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=str(exception)) from None
    job.task = asyncio.create_task(
        run_live_job(job, runtime, request.app.state.device, source_path, sampleFps)
    )
    return LiveVideoStart(
        jobId=job.job_id, modelType=canonical_name, originalFileName=file_name, requestedSampleFps=sampleFps
    )


@app.get("/video/live/{job_id}/status")
async def live_video_status(job_id: str) -> dict:
    return require_live_job(job_id).status()


@app.get("/video/live/{job_id}/stream")
async def live_video_stream(job_id: str) -> StreamingResponse:
    """MJPEG stream of the overlay frames; ends after the last frame of the video."""
    job = require_live_job(job_id)

    async def frames():
        sent = 0
        while True:
            seq, jpeg = job.latest()
            if seq != sent and jpeg:
                sent = seq
                yield (
                    f"--{LIVE_STREAM_BOUNDARY}\r\nContent-Type: image/jpeg\r\n"
                    f"Content-Length: {len(jpeg)}\r\n\r\n"
                ).encode("ascii") + jpeg + b"\r\n"
            elif job.finished:
                break
            else:
                await asyncio.sleep(LIVE_STREAM_POLL_SEC)

    return StreamingResponse(
        frames(),
        media_type=f"multipart/x-mixed-replace; boundary={LIVE_STREAM_BOUNDARY}",
        headers={"Cache-Control": "no-store"},
    )


@app.get("/video/live/{job_id}/result", response_model=VideoPredictionResponse)
async def live_video_result(job_id: str, transfer: str = "inline") -> VideoPredictionResponse:
    transfer = check_video_transfer(transfer)
    job = require_live_job(job_id)
    if job.state == "running":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="The live video job is still running")
    if job.state == "error":
        raise HTTPException(status_code=job.error_status or 500, detail=job.error)
    return video_response(job.result, job.model_type, job.file_name, transfer)


app.include_router(
    create_mobile_router(model_config=MODEL_CONFIG, decode_image=decode_image)
)
