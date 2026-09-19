"""
utils.py — Crop, align, and preprocess helpers for MiniFASNetV2 / V2-SE.
Matches the exact Minivision training pipeline: center-expand crop, resize 80x80,
BGR float32 NCHW [0,1].
"""
import cv2
import numpy as np
from typing import Tuple, Optional


def crop_face(
    frame: np.ndarray,
    bbox,
    scale: float,
    target_size: Tuple[int, int] = (80, 80),
) -> Optional[np.ndarray]:
    """
    Minivision-exact face crop: center the bbox, expand by 'scale', and shift
    boundaries to keep aspect ratio when edges hit frame limits.

    Args:
        frame:       Full BGR frame.
        bbox:        [x1, y1, x2, y2] (InsightFace) OR [x, y, w, h].
        scale:       2.7 for MiniFASNetV2, 4.0 for MiniFASNetV2-SE.
        target_size: Final resize (80, 80).

    Returns:
        Cropped, resized BGR uint8 array or None on failure.
    """
    if frame is None or frame.size == 0:
        return None
    try:
        src_h, src_w = frame.shape[:2]
        b = [float(v) for v in bbox[:4]]

        # Auto-detect [x1, y1, x2, y2] vs [x, y, w, h]
        # If right coordinate > left coordinate and bottom coordinate > top coordinate, it's [x1, y1, x2, y2]
        if b[2] > b[0] and b[3] > b[1]:
            x, y = b[0], b[1]
            box_w = b[2] - b[0]
            box_h = b[3] - b[1]
        else:
            x, y, box_w, box_h = b[0], b[1], b[2], b[3]

        if box_w <= 0 or box_h <= 0:
            return None

        # Minivision scale clamping to prevent out-of-bounds explosion
        scale = min((src_h - 1) / max(1.0, box_h), min((src_w - 1) / max(1.0, box_w), scale))

        new_width = box_w * scale
        new_height = box_h * scale
        center_x = box_w / 2.0 + x
        center_y = box_h / 2.0 + y

        left_top_x = center_x - new_width / 2.0
        left_top_y = center_y - new_height / 2.0
        right_bottom_x = center_x + new_width / 2.0
        right_bottom_y = center_y + new_height / 2.0

        # Boundary shift to keep square crop intact
        if left_top_x < 0:
            right_bottom_x -= left_top_x
            left_top_x = 0

        if left_top_y < 0:
            right_bottom_y -= left_top_y
            left_top_y = 0

        if right_bottom_x > src_w - 1:
            left_top_x -= right_bottom_x - src_w + 1
            right_bottom_x = src_w - 1

        if right_bottom_y > src_h - 1:
            left_top_y -= right_bottom_y - src_h + 1
            right_bottom_y = src_h - 1

        x1 = max(0, int(left_top_x))
        y1 = max(0, int(left_top_y))
        x2 = min(src_w, int(right_bottom_x) + 1)
        y2 = min(src_h, int(right_bottom_y) + 1)

        if x2 - x1 < 10 or y2 - y1 < 10:
            return None

        crop = frame[y1:y2, x1:x2]
        ch, cw = crop.shape[:2]
        # Choose high-quality interpolation: AREA for downsampling, CUBIC for upsampling low-res crops
        interp = cv2.INTER_AREA if (ch >= target_size[1] and cw >= target_size[0]) else cv2.INTER_CUBIC
        return cv2.resize(crop, target_size, interpolation=interp)
    except Exception:
        return None


def preprocess(crop: np.ndarray) -> np.ndarray:
    """
    Prepare an 80x80 BGR crop for ONNX inference.
    CRITICAL: MiniFASNet was trained on unnormalized raw [0, 255] float tensors (no division by 255).
    Returns float32 NCHW tensor (1, 3, 80, 80) in [0.0, 255.0].
    """
    t = crop.astype(np.float32)
    t = t.transpose(2, 0, 1)          # HWC → CHW
    return np.expand_dims(t, axis=0)  # → NCHW


def softmax(logits: np.ndarray) -> np.ndarray:
    """Numerically stable softmax over the last axis."""
    e = np.exp(logits - np.max(logits, axis=-1, keepdims=True))
    return e / (e.sum(axis=-1, keepdims=True) + 1e-12)


def apply_adaptive_gamma(
    crop: np.ndarray,
    mean_luma: Optional[float] = None,
    luma_threshold: float = 78.0,
) -> np.ndarray:
    """
    Adaptive gamma compensation for low-light face crops.
    MiniFASNet relies on 3D depth curvature and specular highlights that flatten
    under high camera sensor gain (ISO) in dim rooms.
    Gently lifting luminance dynamic range restores the natural 3D gradient
    without generating the high-frequency edge noise that CLAHE creates.
    """
    if crop is None or crop.size == 0:
        return crop
    try:
        if mean_luma is None:
            gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
            mean_luma = float(np.mean(gray))

        if mean_luma >= luma_threshold:
            return crop

        # Calculate gamma: gentle brightening curve between 0.60 and 0.90 for low light
        gamma = max(0.60, min(0.90, mean_luma / 85.0))
        table = np.array([((i / 255.0) ** gamma) * 255 for i in np.arange(0, 256)]).astype("uint8")
        return cv2.LUT(crop, table)
    except Exception:
        return crop

