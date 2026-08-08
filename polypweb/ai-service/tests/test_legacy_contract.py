from conftest import JPEG_BYTES, upload


def test_01_legacy_health_still_works(app_client):
    client, _ = app_client
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["service"] == "polypvision-ai"
    assert "checkpoint" in response.json()["models"]["YOLO26n-seg"]


def test_02_legacy_predict_keeps_multipart_fields(app_client):
    client, harness = app_client
    response = client.post(
        "/predict",
        data={"modelType": "YOLO26n-seg"},
        files=upload(JPEG_BYTES),
    )
    assert response.status_code == 200
    assert harness.call_order == ["YOLO26n-seg"]


def test_03_legacy_response_fields_are_unchanged(app_client):
    client, _ = app_client
    response = client.post(
        "/predict",
        data={"modelType": "YOLO26n-seg"},
        files=upload(),
    )
    assert set(response.json()) == {
        "success",
        "detected",
        "label",
        "confidence",
        "processingTimeMs",
        "maskCount",
        "modelType",
        "originalFileName",
        "resultImageBase64",
        "message",
    }


def test_04_legacy_validation_keeps_fastapi_detail(app_client):
    client, _ = app_client
    response = client.post("/predict", data={"modelType": "YOLO26n-seg"})
    assert response.status_code == 422
    assert set(response.json()) == {"detail"}
    assert isinstance(response.json()["detail"], list)
