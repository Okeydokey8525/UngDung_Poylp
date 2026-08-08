import json
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeout

from conftest import set_unavailable, upload


def compare(client):
    return client.post("/api/v1/comparison", files=upload())


def test_29_comparison_runs_baseline_then_vmamba(app_client):
    client, harness = app_client
    assert compare(client).status_code == 200
    assert harness.call_order == ["YOLO26n-seg", "YOLO26n-VMamba-seg"]


def test_30_comparison_models_do_not_run_in_parallel(app_client):
    client, harness = app_client
    harness.delay = 0.02
    assert compare(client).status_code == 200
    assert harness.max_active == 1


def test_31_comparison_returns_both_results(app_client):
    client, _ = app_client
    body = compare(client).json()
    assert body["baseline"]["modelKey"] == "YOLO26n-seg"
    assert body["vmamba"]["modelKey"] == "YOLO26n-VMamba-seg"


def test_32_comparison_has_no_winner(app_client):
    client, _ = app_client
    body = compare(client).json()
    assert "winner" not in body
    assert "bestModel" not in body


def test_33_comparison_has_no_best_model_claim(app_client):
    client, _ = app_client
    text = json.dumps(compare(client).json(), ensure_ascii=False).lower()
    assert "tốt hơn" not in text
    assert "recommendation" not in text


def test_34_unavailable_model_rejects_whole_comparison(app_client):
    client, harness = app_client
    set_unavailable("YOLO26n-VMamba-seg")
    response = compare(client)
    assert response.status_code == 503
    assert response.json()["code"] == "MODEL_NOT_READY"
    assert harness.call_order == []


def test_35_comparison_does_not_deadlock(app_client):
    client, _ = app_client
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(compare, client)
        try:
            response = future.result(timeout=2)
        except FutureTimeout:
            assert False, "comparison deadlocked"
    assert response.status_code == 200
