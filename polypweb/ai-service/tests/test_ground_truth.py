from io import BytesIO
from types import SimpleNamespace

import numpy as np
import pytest
import torch
from PIL import Image

from conftest import JPEG_BYTES, upload
from ground_truth import (
    GROUND_TRUTH_COLOR_BGR,
    binarize_ground_truth,
    draw_ground_truth,
    pixel_metrics,
    predicted_mask,
)


def mask_png(size=(13, 7), box=(2, 1, 8, 5)) -> bytes:
    image = Image.new("L", size, 0)
    x0, y0, x1, y1 = box
    for x in range(x0, x1):
        for y in range(y0, y1):
            image.putpixel((x, y), 255)
    output = BytesIO()
    image.save(output, format="PNG")
    return output.getvalue()


def test_01_metrics_match_thesis_formulas():
    gt = np.zeros((4, 4), bool)
    gt[0:2, 0:2] = True          # 4 px
    pred = np.zeros((4, 4), bool)
    pred[0:2, 0:3] = True        # 6 px -> TP 4, FP 2, FN 0
    m = pixel_metrics(pred, gt)
    assert (m["truePositivePixels"], m["falsePositivePixels"], m["falseNegativePixels"]) == (4, 2, 0)
    assert m["dice"] == pytest.approx(8 / 10)
    assert m["iou"] == pytest.approx(4 / 6)
    assert m["precision"] == pytest.approx(4 / 6)
    assert m["recall"] == pytest.approx(1.0)
    assert m["backgroundImage"] is False


def test_02_missed_polyp_gives_zero_precision_and_dice():
    gt = np.zeros((3, 3), bool)
    gt[1, 1] = True
    m = pixel_metrics(np.zeros((3, 3), bool), gt)
    assert m["dice"] == 0.0 and m["iou"] == 0.0 and m["recall"] == 0.0
    assert m["precision"] == 0.0


def test_03_background_mask_leaves_ratios_undefined():
    m = pixel_metrics(np.zeros((3, 3), bool), np.zeros((3, 3), bool))
    assert m["dice"] is None and m["iou"] is None and m["precision"] is None and m["recall"] is None
    assert m["backgroundImage"] is True
    fp = np.zeros((3, 3), bool)
    fp[0, 0] = True
    m = pixel_metrics(fp, np.zeros((3, 3), bool))
    assert m["falsePositivePixels"] == 1 and m["precision"] == 0.0 and m["dice"] == 0.0


def test_04_binarize_uses_threshold_127():
    image = Image.new("L", (3, 1))
    image.putdata([127, 128, 255])
    assert binarize_ground_truth(image).tolist() == [[False, True, True]]


def test_05_predicted_mask_merges_instances():
    data = torch.zeros((2, 4, 5))
    data[0, 0, 0] = 0.9
    data[1, 3, 4] = 0.6
    data[1, 2, 2] = 0.4          # below 0.5
    result = SimpleNamespace(masks=SimpleNamespace(data=data))
    merged = predicted_mask(result, 4, 5)
    assert merged.sum() == 2 and merged[0, 0] and merged[3, 4]
    assert predicted_mask(SimpleNamespace(masks=None), 4, 5).sum() == 0


def test_06_ground_truth_outline_is_drawn_in_green():
    image = np.zeros((40, 40, 3), np.uint8)
    gt = np.zeros((40, 40), bool)
    gt[10:30, 10:30] = True
    drawn = draw_ground_truth(image.copy(), gt)
    assert (drawn == np.array(GROUND_TRUTH_COLOR_BGR, np.uint8)).all(axis=2).any()
    assert draw_ground_truth(image.copy(), np.zeros((40, 40), bool)).sum() == 0


def test_07_endpoint_passes_ground_truth_and_returns_metrics(app_client):
    client, harness = app_client
    harness.overrides["YOLO26s-seg"] = {"groundTruthMetrics": pixel_metrics(
        np.ones((7, 13), bool), binarize_ground_truth(Image.open(BytesIO(mask_png()))))}
    files = upload(JPEG_BYTES)
    files["groundTruth"] = ("mask.png", mask_png(), "image/png")
    response = client.post("/predict", data={"modelType": "YOLO26s-seg"}, files=files)
    assert response.status_code == 200, response.text
    assert harness.last_ground_truth is not None
    assert harness.last_ground_truth.shape == (7, 13)
    assert int(harness.last_ground_truth.sum()) == 6 * 4
    metrics = response.json()["groundTruthMetrics"]
    assert metrics["groundTruthPixels"] == 24 and metrics["recall"] == 1.0


def test_08_endpoint_rejects_mask_of_another_size(app_client):
    client, harness = app_client
    files = upload(JPEG_BYTES)
    files["groundTruth"] = ("mask.png", mask_png(size=(20, 20)), "image/png")
    response = client.post("/predict", data={"modelType": "YOLO26s-seg"}, files=files)
    assert response.status_code == 422
    assert "20x20" in response.json()["detail"]
    assert harness.call_order == []


def test_09_without_mask_no_ground_truth_reaches_inference(app_client):
    client, harness = app_client
    response = client.post("/predict", data={"modelType": "YOLO26s-seg"}, files=upload())
    assert response.status_code == 200
    assert harness.last_ground_truth is None
    assert "groundTruthMetrics" not in response.json()
