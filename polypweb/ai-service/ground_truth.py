"""Optional ground-truth comparison for a single image.

Follows the thesis pixel protocol (CNTT_KLCN182_PhungTheBao/00_tai_lieu_tong_quan/scripts/danh_gia_pixel.py):
- ground truth: grayscale mask binarised at > 127, same size as the image;
- prediction: every predicted instance mask at the original resolution (retina masks, > 0.5) merged into one;
- Dice = 2TP / (2TP + FP + FN), IoU = TP / (TP + FP + FN), Precision = TP / (TP + FP), Recall = TP / (TP + FN).
  On a polyp image with no prediction, Precision is 0 (as in the thesis). Undefined ratios
  (e.g. every metric on a background mask with no prediction) are returned as None.
"""
from __future__ import annotations

from typing import Any

import cv2
import numpy as np
from PIL import Image

GROUND_TRUTH_COLOR_BGR = (0, 200, 0)  # green outline; the prediction outline is yellow


def binarize_ground_truth(mask_image: Image.Image) -> np.ndarray:
    return np.asarray(mask_image.convert("L")) > 127


def predicted_mask(result: Any, height: int, width: int) -> np.ndarray:
    merged = np.zeros((height, width), dtype=bool)
    masks = getattr(result, "masks", None)
    data = getattr(masks, "data", None) if masks is not None else None
    if data is None or len(data) == 0:
        return merged
    stacked = data.detach().cpu().numpy() > 0.5
    if stacked.shape[1:] != (height, width):
        # retina_masks=True should already give the original size; resize defensively otherwise.
        stacked = np.stack([
            cv2.resize(m.astype(np.uint8), (width, height), interpolation=cv2.INTER_NEAREST) > 0
            for m in stacked
        ])
    return stacked.any(axis=0)


def _ratio(numerator: int, denominator: int) -> float | None:
    return numerator / denominator if denominator else None


def pixel_metrics(pred: np.ndarray, gt: np.ndarray) -> dict[str, Any]:
    if pred.shape != gt.shape:
        raise ValueError("prediction and ground truth must have the same shape")
    tp = int(np.logical_and(pred, gt).sum())
    fp = int(np.logical_and(pred, ~gt).sum())
    fn = int(np.logical_and(~pred, gt).sum())
    gt_pixels = int(gt.sum())
    precision = _ratio(tp, tp + fp)
    if precision is None and gt_pixels > 0:
        precision = 0.0
    return {
        "dice": _ratio(2 * tp, 2 * tp + fp + fn),
        "iou": _ratio(tp, tp + fp + fn),
        "precision": precision,
        "recall": _ratio(tp, tp + fn),
        "truePositivePixels": tp,
        "falsePositivePixels": fp,
        "falseNegativePixels": fn,
        "groundTruthPixels": gt_pixels,
        "predictedPixels": int(pred.sum()),
        "imagePixels": int(gt.size),
        "backgroundImage": gt_pixels == 0,
    }


def draw_ground_truth(image_bgr: np.ndarray, gt: np.ndarray) -> np.ndarray:
    if not gt.any():
        return image_bgr
    outlined = np.ascontiguousarray(image_bgr)
    if outlined.shape[:2] != gt.shape:
        gt = cv2.resize(gt.astype(np.uint8), (outlined.shape[1], outlined.shape[0]),
                        interpolation=cv2.INTER_NEAREST) > 0
    contours, _ = cv2.findContours(gt.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    thickness = max(2, round(max(outlined.shape[:2]) / 300))
    cv2.drawContours(outlined, contours, -1, GROUND_TRUTH_COLOR_BGR, thickness, lineType=cv2.LINE_AA)
    return outlined
