from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


RESEARCH_WARNING = (
    "Kết quả chỉ phục vụ nghiên cứu và hỗ trợ tham khảo, không thay thế "
    "chẩn đoán hoặc quyết định chuyên môn của bác sĩ."
)


class MobileErrorResponse(BaseModel):
    requestId: str
    status: int
    code: str
    message: str
    fieldErrors: dict[str, str] = Field(default_factory=dict)


class MobileHealthResponse(BaseModel):
    requestId: str
    status: str
    service: str
    ready: bool
    device: str
    readyModels: int
    totalModels: int
    timestamp: datetime


class MobileModelResponse(BaseModel):
    key: str
    name: str
    family: str
    ready: bool


class MobileModelsResponse(BaseModel):
    requestId: str
    models: list[MobileModelResponse]


class MobileOverlayResponse(BaseModel):
    mediaType: str = "image/jpeg"
    encoding: str = "base64"
    data: str


class MobileModelResultResponse(BaseModel):
    modelKey: str
    modelName: str
    modelFamily: str
    detected: bool
    label: str | None
    confidence: float
    maskCount: int
    processingTimeMs: float
    overlay: MobileOverlayResponse


class MobileInferenceResponse(MobileModelResultResponse):
    requestId: str
    originalFileName: str
    originalWidth: int
    originalHeight: int
    warning: str = RESEARCH_WARNING


class MobileComparisonResponse(BaseModel):
    requestId: str
    originalFileName: str
    originalWidth: int
    originalHeight: int
    totalProcessingTimeMs: float
    baseline: MobileModelResultResponse
    vmamba: MobileModelResultResponse
    warning: str = RESEARCH_WARNING
