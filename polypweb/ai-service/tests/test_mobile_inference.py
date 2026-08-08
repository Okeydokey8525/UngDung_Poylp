import base64
import json

from starlette.datastructures import UploadFile as StarletteUploadFile

from conftest import (
    JPEG_BYTES,
    PNG_BYTES,
    oversized_pixel_png_bytes,
    set_unavailable,
    upload,
)


def infer(client, key="YOLO26n-seg", files=None):
    return client.post(
        "/api/v1/inference",
        data={"modelKey": key},
        files=files or upload(),
    )


def test_10_valid_jpg_baseline(app_client):
    client, _ = app_client
    response = infer(client)
    assert response.status_code == 200
    assert response.json()["modelKey"] == "YOLO26n-seg"


def test_11_valid_jpg_vmamba(app_client):
    client, _ = app_client
    response = infer(client, "YOLO26n-VMamba-seg")
    assert response.status_code == 200
    assert response.json()["modelFamily"] == "vmamba"


def test_12_valid_png(app_client):
    client, _ = app_client
    response = infer(
        client,
        files=upload(PNG_BYTES, filename="sample.png", content_type="image/png"),
    )
    assert response.status_code == 200
    assert response.json()["originalFileName"] == "sample.png"


def test_13_overlay_media_type_is_jpeg(app_client):
    client, _ = app_client
    assert infer(client).json()["overlay"]["mediaType"] == "image/jpeg"


def test_14_overlay_base64_decodes_to_jpeg(app_client):
    client, _ = app_client
    data = base64.b64decode(infer(client).json()["overlay"]["data"], validate=True)
    assert data[:3] == b"\xff\xd8\xff"


def test_15_detected_false_keeps_complete_schema(app_client):
    client, harness = app_client
    harness.overrides["YOLO26n-seg"] = {
        "detected": False,
        "label": "should-not-leak",
        "confidence": 0.8,
        "maskCount": 4,
    }
    body = infer(client).json()
    assert body["detected"] is False
    assert body["label"] is None
    assert body["confidence"] == 0
    assert body["maskCount"] == 0
    assert body["overlay"]["data"]


def test_16_original_dimensions_are_correct(app_client):
    client, _ = app_client
    body = infer(client).json()
    assert (body["originalWidth"], body["originalHeight"]) == (13, 7)


def test_17_model_key_is_canonical(app_client):
    client, _ = app_client
    assert infer(client, "yolo26N-SEG").json()["modelKey"] == "YOLO26n-seg"


def test_18_unknown_model(app_client):
    client, _ = app_client
    response = infer(client, "unknown")
    assert response.status_code == 404
    assert response.json()["code"] == "MODEL_NOT_FOUND"


def test_19_model_unavailable(app_client):
    client, _ = app_client
    set_unavailable("YOLO26n-seg")
    response = infer(client)
    assert response.status_code == 503
    assert response.json()["code"] == "MODEL_NOT_READY"


def test_20_empty_file(app_client):
    client, _ = app_client
    response = infer(client, files=upload(b""))
    assert response.status_code == 422
    assert response.json()["code"] == "INVALID_IMAGE"


def test_21_file_over_ten_megabytes(app_client):
    client, _ = app_client
    response = infer(client, files=upload(b"x" * (10 * 1024 * 1024 + 1)))
    assert response.status_code == 413
    assert response.json()["code"] == "FILE_TOO_LARGE"


def test_22_wrong_mime(app_client):
    client, _ = app_client
    response = infer(client, files=upload(content_type="text/plain"))
    assert response.status_code == 415
    assert response.json()["code"] == "UNSUPPORTED_MEDIA_TYPE"


def test_23_mime_does_not_match_content(app_client):
    client, _ = app_client
    response = infer(client, files=upload(PNG_BYTES, content_type="image/jpeg"))
    assert response.status_code == 415
    assert response.json()["code"] == "UNSUPPORTED_MEDIA_TYPE"


def test_24_non_image_file(app_client):
    client, _ = app_client
    response = infer(client, files=upload(b"not an image"))
    assert response.status_code == 422
    assert response.json()["code"] == "INVALID_IMAGE"


def test_25_image_over_pixel_limit(app_client):
    client, _ = app_client
    response = infer(
        client,
        files=upload(
            oversized_pixel_png_bytes(),
            filename="large.png",
            content_type="image/png",
        ),
    )
    assert response.status_code == 422
    assert response.json()["code"] == "INVALID_IMAGE"


def test_26_upload_is_closed_on_success(app_client, monkeypatch):
    client, _ = app_client
    calls = []
    original = StarletteUploadFile.close

    async def tracked(self):
        calls.append(self.filename)
        await original(self)

    monkeypatch.setattr(StarletteUploadFile, "close", tracked)
    assert infer(client).status_code == 200
    assert "sample.jpg" in calls


def test_27_upload_is_closed_on_error(app_client, monkeypatch):
    client, _ = app_client
    calls = []
    original = StarletteUploadFile.close

    async def tracked(self):
        calls.append(self.filename)
        await original(self)

    monkeypatch.setattr(StarletteUploadFile, "close", tracked)
    assert infer(client, "unknown").status_code == 404
    assert "sample.jpg" in calls


def test_28_response_does_not_leak_internal_paths(app_client):
    client, _ = app_client
    text = json.dumps(infer(client).json()).lower()
    assert "checkpoint" not in text
    assert "traceback" not in text
    assert "c:\\" not in text
    assert "storage/" not in text
