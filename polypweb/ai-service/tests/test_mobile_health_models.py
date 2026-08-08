import json

from conftest import set_unavailable


def test_05_mobile_health_hides_checkpoint_name(app_client):
    client, _ = app_client
    body = client.get("/api/v1/health").json()
    assert "checkpoint" not in json.dumps(body).lower()


def test_06_mobile_health_hides_hash(app_client):
    client, _ = app_client
    body = client.get("/api/v1/health").json()
    assert "sha" not in json.dumps(body).lower()
    assert "FAKE-SHA256" not in json.dumps(body)


def test_07_mobile_health_hides_raw_model_error(app_client):
    client, _ = app_client
    set_unavailable("YOLO26n-VMamba-seg", "C:\\secret\\model.pt traceback")
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json()["status"] == "degraded"
    assert "secret" not in json.dumps(response.json()).lower()


def test_08_models_returns_exact_two_keys(app_client):
    client, _ = app_client
    models = client.get("/api/v1/models").json()["models"]
    assert [item["key"] for item in models] == [
        "YOLO26n-seg",
        "YOLO26n-VMamba-seg",
    ]


def test_09_models_readiness_comes_from_registry(app_client):
    client, _ = app_client
    set_unavailable("YOLO26n-VMamba-seg")
    models = client.get("/api/v1/models").json()["models"]
    assert models[0]["ready"] is True
    assert models[1]["ready"] is False
