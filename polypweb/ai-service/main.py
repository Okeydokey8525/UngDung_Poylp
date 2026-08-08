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
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from time import perf_counter
from typing import Any

import numpy as np
import torch
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile, status
from fastapi.exception_handlers import (
    http_exception_handler,
    request_validation_exception_handler,
)
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel

from mobile_contract import MobileErrorResponse
from mobile_routes import MobileApiError, create_mobile_router

PIL_IMAGE_OPEN = Image.open

BASE_DIR = Path(__file__).resolve().parent
VMAMBA_MODULE_PATH = BASE_DIR / "custom_ultralytics" / "vmamba.py"


def register_vmamba_module() -> None:
    """Register the vendored custom class at the module path stored in the checkpoint."""
    import ultralytics.nn.modules as modules_package

    module_name = "ultralytics.nn.modules.vmamba"
    if module_name in sys.modules:
        return
    if not VMAMBA_MODULE_PATH.is_file():
        raise RuntimeError(f"VMamba module was not found: {VMAMBA_MODULE_PATH}")

    module_spec = importlib.util.spec_from_file_location(module_name, VMAMBA_MODULE_PATH)
    if module_spec is None or module_spec.loader is None:
        raise RuntimeError("Could not create the VMamba module specification")

    vmamba_module = importlib.util.module_from_spec(module_spec)
    sys.modules[module_name] = vmamba_module
    try:
        module_spec.loader.exec_module(vmamba_module)
    except Exception:
        sys.modules.pop(module_name, None)
        raise

    setattr(modules_package, "vmamba", vmamba_module)
    setattr(modules_package, "VMambaBlock", vmamba_module.VMambaBlock)


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
    "YOLO26n-seg": ModelConfig(
        path=Path(
            os.getenv(
                "AI_BASELINE_MODEL_PATH",
                os.getenv(
                    "AI_MODEL_PATH",
                    str(BASE_DIR / "models" / "yolo26n-seg-best.pt"),
                ),
            )
        )
        .expanduser()
        .resolve(),
        family="baseline",
    ),
    "YOLO26n-VMamba-seg": ModelConfig(
        path=Path(
            os.getenv(
                "AI_VMAMBA_MODEL_PATH",
                str(BASE_DIR / "models" / "yolo26n-vmamba-seg-best.pt"),
            )
        )
        .expanduser()
        .resolve(),
        family="vmamba",
    ),
}


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
    description="Real baseline and VMamba segmentation service for PolypVision stage 3D.",
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


def encode_result_image(result: Any) -> str:
    plotted_bgr = result.plot()
    if plotted_bgr is None or plotted_bgr.size == 0:
        raise RuntimeError("The model produced an empty result image")

    plotted_rgb = np.ascontiguousarray(plotted_bgr[..., ::-1])
    output = BytesIO()
    Image.fromarray(plotted_rgb).save(output, format="JPEG", quality=90)
    return base64.b64encode(output.getvalue()).decode("ascii")


def run_inference(
    model: YOLO,
    device: str,
    decoded_image: Image.Image,
) -> dict[str, Any]:
    input_array = np.asarray(decoded_image)
    inference_started = perf_counter()
    results = model.predict(
        source=input_array,
        conf=CONFIDENCE_THRESHOLD,
        imgsz=INFERENCE_IMAGE_SIZE,
        device=device,
        verbose=False,
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

    return {
        "detected": detected,
        "label": label,
        "confidence": confidence,
        "processingTimeMs": round(inference_time_ms, 3),
        "maskCount": mask_count,
        "resultImageBase64": encode_result_image(result),
    }


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


@app.post("/predict", response_model=PredictionResponse)
async def predict(
    request: Request,
    image: UploadFile = File(...),
    modelType: str = Form(...),
) -> PredictionResponse:
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

    decoded_image = decode_image(content, image.content_type)
    try:
        async with runtime.lock:
            prediction = await asyncio.to_thread(
                run_inference,
                runtime.model,
                request.app.state.device,
                decoded_image,
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
    return PredictionResponse(
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


app.include_router(
    create_mobile_router(model_config=MODEL_CONFIG, decode_image=decode_image)
)
