from __future__ import annotations

import asyncio
import base64
import binascii
import math
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Mapping

from fastapi import APIRouter, File, Form, Request, Response, UploadFile

from mobile_contract import (
    MobileComparisonResponse,
    MobileHealthResponse,
    MobileInferenceResponse,
    MobileModelResponse,
    MobileModelResultResponse,
    MobileModelsResponse,
    MobileOverlayResponse,
)


BASELINE_MODEL_KEY = "YOLO26n-seg"
VMAMBA_MODEL_KEY = "YOLO26n-VMamba-seg"
MOBILE_MODEL_KEYS = (BASELINE_MODEL_KEY, VMAMBA_MODEL_KEY)
MODEL_DISPLAY_NAMES = {
    BASELINE_MODEL_KEY: "YOLO26n-seg",
    VMAMBA_MODEL_KEY: "YOLO26n-seg + VMamba",
}


class MobileApiError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        field_errors: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.field_errors = field_errors or {}


def create_mobile_router(
    *,
    model_config: Mapping[str, Any],
    decode_image: Callable[[bytes, str], Any],
) -> APIRouter:
    router = APIRouter(prefix="/api/v1")

    @router.get("/health", response_model=MobileHealthResponse)
    async def mobile_health(request: Request, response: Response) -> MobileHealthResponse:
        models = request.app.state.models
        ready_count = sum(_runtime_ready(models.get(key)) for key in MOBILE_MODEL_KEYS)
        total_models = len(MOBILE_MODEL_KEYS)
        if ready_count == total_models:
            health_status = "ok"
        elif ready_count > 0:
            health_status = "degraded"
        else:
            health_status = "unavailable"
            response.status_code = 503
        return MobileHealthResponse(
            requestId=_request_id(request),
            status=health_status,
            service="PolypVision AI Service",
            ready=ready_count == total_models,
            device=_public_device(getattr(request.app.state, "device", "unknown")),
            readyModels=ready_count,
            totalModels=total_models,
            timestamp=datetime.now(timezone.utc),
        )

    @router.get("/models", response_model=MobileModelsResponse)
    async def mobile_models(request: Request) -> MobileModelsResponse:
        runtimes = request.app.state.models
        return MobileModelsResponse(
            requestId=_request_id(request),
            models=[
                MobileModelResponse(
                    key=key,
                    name=MODEL_DISPLAY_NAMES[key],
                    family=model_config[key].family,
                    ready=_runtime_ready(runtimes.get(key)),
                )
                for key in MOBILE_MODEL_KEYS
            ],
        )

    @router.post("/inference", response_model=MobileInferenceResponse)
    async def mobile_inference(
        request: Request,
        image: UploadFile = File(...),
        modelKey: str = Form(...),
    ) -> MobileInferenceResponse:
        try:
            canonical_key, runtime = _find_runtime(request, modelKey)
            decoded, safe_name = await _read_image(image, decode_image)
            async with _inference_capacity(request):
                prediction = await _run_model(request, runtime, decoded)
            result = _model_result(canonical_key, runtime, prediction)
            return MobileInferenceResponse(
                requestId=_request_id(request),
                originalFileName=safe_name,
                originalWidth=decoded.width,
                originalHeight=decoded.height,
                **result.model_dump(),
            )
        finally:
            await image.close()

    @router.post("/comparison", response_model=MobileComparisonResponse)
    async def mobile_comparison(
        request: Request,
        image: UploadFile = File(...),
    ) -> MobileComparisonResponse:
        try:
            baseline_key, baseline_runtime = _find_runtime(
                request, BASELINE_MODEL_KEY
            )
            vmamba_key, vmamba_runtime = _find_runtime(request, VMAMBA_MODEL_KEY)
            decoded, safe_name = await _read_image(image, decode_image)
            async with _inference_capacity(request):
                baseline_prediction = await _run_model(
                    request, baseline_runtime, decoded
                )
                vmamba_prediction = await _run_model(request, vmamba_runtime, decoded)
            baseline = _model_result(
                baseline_key, baseline_runtime, baseline_prediction
            )
            vmamba = _model_result(vmamba_key, vmamba_runtime, vmamba_prediction)
            total_time = _finite_number(
                baseline.processingTimeMs + vmamba.processingTimeMs,
                "processingTimeMs",
            )
            return MobileComparisonResponse(
                requestId=_request_id(request),
                originalFileName=safe_name,
                originalWidth=decoded.width,
                originalHeight=decoded.height,
                totalProcessingTimeMs=round(total_time, 3),
                baseline=baseline,
                vmamba=vmamba,
            )
        finally:
            await image.close()

    return router


async def _read_image(
    image: UploadFile,
    decode_image: Callable[[bytes, str], Any],
) -> tuple[Any, str]:
    content_type = (image.content_type or "").lower()
    if content_type not in {"image/jpeg", "image/png"}:
        raise MobileApiError(
            415,
            "UNSUPPORTED_MEDIA_TYPE",
            "Chỉ hỗ trợ ảnh JPG, JPEG hoặc PNG.",
            {"image": "Content-Type phải là image/jpeg hoặc image/png."},
        )
    content = await image.read(10 * 1024 * 1024 + 1)
    if not content:
        raise MobileApiError(
            422,
            "INVALID_IMAGE",
            "Tệp tải lên không phải ảnh hợp lệ.",
            {"image": "Tệp ảnh không được để trống."},
        )
    if len(content) > 10 * 1024 * 1024:
        raise MobileApiError(
            413,
            "FILE_TOO_LARGE",
            "Dung lượng ảnh vượt quá 10 MB.",
            {"image": "Dung lượng tối đa là 10 MB."},
        )
    try:
        decoded = decode_image(content, content_type)
    except MobileApiError:
        raise
    except Exception as exception:
        status_code = getattr(exception, "status_code", 422)
        if status_code == 415:
            raise MobileApiError(
                415,
                "UNSUPPORTED_MEDIA_TYPE",
                "MIME khai báo không khớp nội dung ảnh hoặc định dạng không được hỗ trợ.",
                {"image": "Ảnh phải là JPG, JPEG hoặc PNG hợp lệ."},
            ) from None
        raise MobileApiError(
            422,
            "INVALID_IMAGE",
            "Tệp tải lên không phải ảnh hợp lệ.",
            {"image": "Không thể giải mã nội dung ảnh."},
        ) from None
    return decoded, _safe_file_name(image.filename)


def _find_runtime(request: Request, requested_key: str) -> tuple[str, Any]:
    normalized = (requested_key or "").strip()
    canonical = next(
        (key for key in MOBILE_MODEL_KEYS if key.casefold() == normalized.casefold()),
        None,
    )
    if canonical is None:
        raise MobileApiError(
            404,
            "MODEL_NOT_FOUND",
            "Không tìm thấy mô hình được yêu cầu.",
            {"modelKey": "Model key không được hỗ trợ."},
        )
    runtime = request.app.state.models.get(canonical)
    if not _runtime_ready(runtime):
        raise MobileApiError(
            503,
            "MODEL_NOT_READY",
            "Mô hình được yêu cầu hiện chưa sẵn sàng.",
            {"modelKey": canonical},
        )
    return canonical, runtime


@asynccontextmanager
async def _inference_capacity(request: Request):
    semaphore = request.app.state.mobile_inference_semaphore
    timeout = request.app.state.mobile_queue_timeout_seconds
    try:
        await asyncio.wait_for(semaphore.acquire(), timeout=timeout)
    except TimeoutError:
        raise MobileApiError(
            503,
            "SERVICE_BUSY",
            "Dịch vụ AI đang bận, vui lòng thử lại sau.",
        ) from None
    try:
        yield
    finally:
        semaphore.release()


async def _run_model(request: Request, runtime: Any, decoded_image: Any) -> dict[str, Any]:
    # Lock order is always: global semaphore -> one model lock -> inference.
    async with runtime.lock:
        run_inference = request.app.state.mobile_run_inference
        task = asyncio.create_task(
            asyncio.to_thread(
                run_inference,
                runtime.model,
                request.app.state.device,
                decoded_image,
            )
        )
        timeout = request.app.state.mobile_inference_timeout_seconds
        try:
            return await asyncio.wait_for(asyncio.shield(task), timeout=timeout)
        except TimeoutError:
            # A worker/GPU inference cannot be cancelled safely. Keep both guards until
            # the worker ends so another inference cannot overlap the timed-out task.
            try:
                await asyncio.shield(task)
            except Exception:
                pass
            raise MobileApiError(
                504,
                "TIMEOUT",
                "Mô hình xử lý quá thời gian cho phép.",
            ) from None
        except asyncio.CancelledError:
            try:
                await asyncio.shield(task)
            finally:
                raise
        except MobileApiError:
            raise
        except Exception:
            raise MobileApiError(
                500,
                "INFERENCE_FAILED",
                "Mô hình không thể xử lý ảnh này.",
            ) from None


def _model_result(
    model_key: str,
    runtime: Any,
    prediction: Mapping[str, Any],
) -> MobileModelResultResponse:
    detected = prediction.get("detected") is True
    confidence = _finite_number(prediction.get("confidence", 0.0), "confidence")
    if confidence < 0 or confidence > 1:
        raise MobileApiError(500, "INFERENCE_FAILED", "Kết quả inference không hợp lệ.")
    processing_time = _finite_number(
        prediction.get("processingTimeMs", 0.0), "processingTimeMs"
    )
    if processing_time < 0:
        raise MobileApiError(500, "INFERENCE_FAILED", "Kết quả inference không hợp lệ.")
    raw_mask_count = prediction.get("maskCount", 0)
    if isinstance(raw_mask_count, bool) or not isinstance(raw_mask_count, int):
        raise MobileApiError(500, "INFERENCE_FAILED", "Kết quả inference không hợp lệ.")
    mask_count = max(0, raw_mask_count) if detected else 0
    overlay_data = prediction.get("resultImageBase64")
    if not _valid_jpeg_base64(overlay_data):
        raise MobileApiError(500, "INFERENCE_FAILED", "Ảnh overlay không hợp lệ.")
    label = prediction.get("label")
    if label is not None:
        label = str(label).strip() or None
    return MobileModelResultResponse(
        modelKey=model_key,
        modelName=MODEL_DISPLAY_NAMES[model_key],
        modelFamily=runtime.config.family,
        detected=detected,
        label=label if detected else None,
        confidence=confidence if detected else 0.0,
        maskCount=mask_count,
        processingTimeMs=round(processing_time, 3),
        overlay=MobileOverlayResponse(data=overlay_data),
    )


def _finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise MobileApiError(500, "INFERENCE_FAILED", f"{field} không hợp lệ.")
    result = float(value)
    if not math.isfinite(result):
        raise MobileApiError(500, "INFERENCE_FAILED", f"{field} không hợp lệ.")
    return result


def _valid_jpeg_base64(value: Any) -> bool:
    if not isinstance(value, str) or not value or value.startswith("data:"):
        return False
    try:
        decoded = base64.b64decode(value, validate=True)
    except (ValueError, binascii.Error):
        return False
    return len(decoded) >= 3 and decoded[:3] == b"\xff\xd8\xff"


def _runtime_ready(runtime: Any) -> bool:
    return runtime is not None and runtime.status == "ready" and runtime.model is not None


def _safe_file_name(value: str | None) -> str:
    normalized = (value or "uploaded-image.jpg").replace("\\", "/")
    name = normalized.rsplit("/", 1)[-1]
    name = name.replace("\r", "").replace("\n", "").replace('"', "'").strip()
    if not name or name in {".", ".."}:
        return "uploaded-image.jpg"
    return Path(name).name[:255]


def _request_id(request: Request) -> str:
    return request.state.request_id


def _public_device(value: Any) -> str:
    normalized = str(value or "unknown").strip().lower()
    if normalized.startswith("cuda"):
        return "cuda"
    if normalized == "cpu":
        return "cpu"
    if normalized in {"mps", "xpu"}:
        return normalized
    return "unknown"
