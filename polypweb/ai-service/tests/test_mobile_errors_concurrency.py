import asyncio
import json
import time
from concurrent.futures import ThreadPoolExecutor

import main
from conftest import upload


def infer(client):
    return client.post(
        "/api/v1/inference",
        data={"modelKey": "YOLO26n-seg"},
        files=upload(),
    )


def compare(client):
    return client.post("/api/v1/comparison", files=upload())


def test_36_error_envelope_is_stable(app_client):
    client, _ = app_client
    body = client.post(
        "/api/v1/inference",
        data={"modelKey": "missing"},
        files=upload(),
    ).json()
    assert set(body) == {"requestId", "status", "code", "message", "fieldErrors"}


def test_37_missing_field_uses_mobile_validation_envelope(app_client):
    client, _ = app_client
    response = client.post("/api/v1/inference", data={"modelKey": "YOLO26n-seg"})
    assert response.status_code == 422
    assert response.json()["code"] == "VALIDATION_ERROR"
    assert "image" in response.json()["fieldErrors"]


def test_38_request_id_is_in_response_header(app_client):
    client, _ = app_client
    response = client.get("/api/v1/models")
    assert response.headers["X-Request-ID"]


def test_39_request_id_is_in_response_body(app_client):
    client, _ = app_client
    response = client.get("/api/v1/models")
    assert response.json()["requestId"] == response.headers["X-Request-ID"]


def test_40_valid_client_request_id_is_preserved(app_client):
    client, _ = app_client
    response = client.get(
        "/api/v1/models", headers={"X-Request-ID": "mobile-request_01"}
    )
    assert response.headers["X-Request-ID"] == "mobile-request_01"
    assert response.json()["requestId"] == "mobile-request_01"


def test_41_invalid_client_request_id_is_replaced(app_client):
    client, _ = app_client
    response = client.get(
        "/api/v1/models", headers={"X-Request-ID": "bad id\r\nsecret"}
    )
    request_id = response.headers["X-Request-ID"]
    assert request_id != "bad id\r\nsecret"
    assert len(request_id) == 36


def test_42_internal_exception_hides_details(app_client):
    client, _ = app_client

    class BrokenRegistry(dict):
        def get(self, key, default=None):
            raise RuntimeError("C:\\checkpoint\\secret.pt traceback")

    original = main.app.state.models
    main.app.state.models = BrokenRegistry(original)
    try:
        response = client.get("/api/v1/models")
    finally:
        main.app.state.models = original
    text = json.dumps(response.json()).lower()
    assert response.status_code == 500
    assert response.json()["code"] == "INTERNAL_ERROR"
    assert "secret" not in text
    assert "traceback" not in text


def test_43_default_mobile_semaphore_is_one(app_client):
    _client, _ = app_client
    assert main.MAX_CONCURRENT_MOBILE_INFERENCE == 1
    assert main.app.state.mobile_inference_semaphore._value == 1


def test_44_two_mobile_inferences_do_not_overlap(app_client):
    client, harness = app_client
    harness.delay = 0.06
    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda _: infer(client), range(2)))
    assert [response.status_code for response in responses] == [200, 200]
    assert harness.max_active == 1


def test_45_comparison_is_atomic_against_other_mobile_inference(app_client):
    client, harness = app_client
    harness.delay = 0.06
    with ThreadPoolExecutor(max_workers=2) as pool:
        comparison_future = pool.submit(compare, client)
        assert harness.started.wait(timeout=1)
        inference_future = pool.submit(infer, client)
        assert comparison_future.result(timeout=3).status_code == 200
        assert inference_future.result(timeout=3).status_code == 200
    assert harness.call_order == [
        "YOLO26n-seg",
        "YOLO26n-VMamba-seg",
        "YOLO26n-seg",
    ]


def test_46_semaphore_wait_timeout_returns_service_busy(app_client):
    client, harness = app_client
    harness.delay = 0.15
    main.app.state.mobile_queue_timeout_seconds = 0.02
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(infer, client)
        assert harness.started.wait(timeout=1)
        second = pool.submit(infer, client)
        second_response = second.result(timeout=2)
        first_response = first.result(timeout=2)
    assert first_response.status_code == 200
    assert second_response.status_code == 503
    assert second_response.json()["code"] == "SERVICE_BUSY"


def test_47_semaphore_is_released_after_inference_error(app_client):
    client, harness = app_client
    harness.failures_remaining = 1
    first = infer(client)
    second = infer(client)
    assert first.status_code == 500
    assert first.json()["code"] == "INFERENCE_FAILED"
    assert second.status_code == 200
    assert main.app.state.mobile_inference_semaphore._value == 1


def test_48_model_lock_is_released_after_inference_error(app_client):
    client, harness = app_client
    harness.failures_remaining = 1
    assert infer(client).status_code == 500
    assert infer(client).status_code == 200
    runtime = main.app.state.models["YOLO26n-seg"]
    assert runtime.lock.locked() is False


def test_49_inference_timeout_waits_for_worker_before_releasing_guards(app_client):
    client, harness = app_client
    harness.delay = 0.06
    main.app.state.mobile_inference_timeout_seconds = 0.01
    started = time.perf_counter()
    response = infer(client)
    elapsed = time.perf_counter() - started
    assert response.status_code == 504
    assert response.json()["code"] == "TIMEOUT"
    assert elapsed >= 0.05
    assert harness.active == 0
    assert main.app.state.mobile_inference_semaphore._value == 1


def test_50_invalid_concurrency_configuration_falls_back_to_one(monkeypatch):
    monkeypatch.setenv("AI_MAX_CONCURRENT_INFERENCE", "invalid")
    assert main.positive_int_setting("AI_MAX_CONCURRENT_INFERENCE", 1) == 1
    monkeypatch.setenv("AI_MAX_CONCURRENT_INFERENCE", "0")
    assert main.positive_int_setting("AI_MAX_CONCURRENT_INFERENCE", 1) == 1
