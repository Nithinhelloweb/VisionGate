"""
ensemble.py — MiniFASNetV2 + MiniFASNetV2-SE geometric mean ensemble.

Each model uses a DIFFERENT crop scale (2.7x vs 4.0x):
  - V2  at 2.7x: tight face crop — skin texture + Fourier artifacts
  - SE  at 4.0x: wider context   — device bezels, screen edges, hand holding photo

The geometric mean √(s_V2 × s_SE) only passes threshold if BOTH models agree.
"""
import math
import numpy as np
from typing import Optional

from .model import AntiSpoofModel
from .utils import crop_face, preprocess, apply_adaptive_gamma
from .config import (
    MODEL_V2,
    MODEL_SE,
    CROP_SCALE_V2,
    CROP_SCALE_SE,
    L1_LIVE_THRESHOLD,
    L1_INPUT_SIZE,
)


class EnsemblePredictor:
    """
    Runs V2 and V2-SE in sequence (thread-safe via thread-local sessions).
    Each instance is safe to share across threads.
    """

    def __init__(
        self,
        model_v2_path: str = MODEL_V2,
        model_se_path: str = MODEL_SE,
        threshold: float = L1_LIVE_THRESHOLD,
    ):
        self._v2 = AntiSpoofModel(model_v2_path)
        self._se = AntiSpoofModel(model_se_path)
        self.threshold = threshold

    def predict(
        self,
        frame: np.ndarray,
        bbox,
    ) -> dict:
        """
        Run both models and return a full result dict.

        Args:
            frame: Full BGR frame (any resolution).
            bbox:  Face bounding box [x1, y1, x2, y2] or [x, y, w, h].

        Returns:
            {
              "score_v2":    float,   # raw liveness score from V2
              "score_se":    float,   # raw liveness score from SE
              "score_final": float,   # geometric mean
              "is_live":     bool,
              "mean_luma":   float,   # average luminance of face crop
            }
        """
        # Crop at scale 2.7 for V2
        crop_27 = crop_face(frame, bbox, CROP_SCALE_V2, L1_INPUT_SIZE)
        # Crop at scale 4.0 for V2-SE
        crop_40 = crop_face(frame, bbox, CROP_SCALE_SE, L1_INPUT_SIZE)

        # Measure luminance of the face crop
        mean_luma = 128.0
        if crop_27 is not None and crop_27.size > 0:
            import cv2
            gray_crop = cv2.cvtColor(crop_27, cv2.COLOR_BGR2GRAY)
            mean_luma = float(np.mean(gray_crop))
            # Apply adaptive gamma compensation if under low-light
            crop_27 = apply_adaptive_gamma(crop_27, mean_luma=mean_luma)
            if crop_40 is not None and crop_40.size > 0:
                crop_40 = apply_adaptive_gamma(crop_40, mean_luma=mean_luma)

        s_v2 = self._v2.predict_score(preprocess(crop_27)) if crop_27 is not None else 0.0
        s_se = self._se.predict_score(preprocess(crop_40)) if crop_40 is not None else 0.0

        # Geometric mean — a single model fooled cannot lift the final above threshold
        score_final = math.sqrt(s_v2 * s_se) if (s_v2 > 0 and s_se > 0) else 0.0

        return {
            "score_v2": round(s_v2, 4),
            "score_se": round(s_se, 4),
            "score_final": round(score_final, 4),
            "is_live": score_final >= self.threshold,
            "mean_luma": round(mean_luma, 1),
        }

    def score_only(self, frame: np.ndarray, bbox) -> float:
        """Convenience: returns the final geometric mean score."""
        return self.predict(frame, bbox)["score_final"]
