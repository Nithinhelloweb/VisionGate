"""
Layer 4 — Optical Flow Temporal Consistency Detector.

Real faces exhibit micro-tremor (involuntary micro-movements, ~0.05-2px/frame).
Video replays on screens have statistically different motion variance:
  - Static photo/mask: σ ~ 0 (no motion at all)
  - Looped video on screen: σ very low or unnaturally periodic
  - Real face: σ in a biological range (0.06 - 9.0)
"""
import cv2
import numpy as np
from collections import deque
from typing import Dict, Optional
from ..config import L4_FLOW_MIN_SIGMA, L4_FLOW_MAX_SIGMA, L4_FLOW_WINDOW_FRAMES


class FlowDetector:
    """
    Stateful, one instance per pipeline worker (NOT thread-safe).
    """

    def __init__(
        self,
        flow_min: float = L4_FLOW_MIN_SIGMA,
        flow_max: float = L4_FLOW_MAX_SIGMA,
        window_frames: int = L4_FLOW_WINDOW_FRAMES,
    ):
        self.flow_min = flow_min
        self.flow_max = flow_max
        self.window_frames = window_frames
        # track_id → deque of per-frame mean optical flow magnitude
        self._buffers: Dict[str, deque] = {}
        # track_id → previous gray face crop
        self._prev_gray: Dict[str, Optional[np.ndarray]] = {}

    def _farneback_mean_mag(self, prev_gray: np.ndarray, curr_gray: np.ndarray) -> float:
        """Compute mean optical flow magnitude between two grayscale crops."""
        try:
            flow = cv2.calcOpticalFlowFarneback(
                prev_gray, curr_gray, None,
                pyr_scale=0.5, levels=3, winsize=15,
                iterations=3, poly_n=5, poly_sigma=1.2,
                flags=0,
            )
            mag, _ = cv2.cartToPolar(flow[..., 0], flow[..., 1])
            return float(mag.mean())
        except Exception:
            return 0.0

    def update(self, track_id: str, face_bgr: np.ndarray) -> dict:
        """
        Process one frame crop for the given track.
        Returns:
          { "sigma": float, "is_live": bool, "frames": int }
        """
        if face_bgr is None or face_bgr.size == 0:
            return {"sigma": 0.0, "is_live": False, "frames": 0}

        curr_gray = cv2.cvtColor(
            cv2.resize(face_bgr, (64, 64)), cv2.COLOR_BGR2GRAY
        )

        if track_id not in self._buffers:
            self._buffers[track_id] = deque(maxlen=self.window_frames)
            self._prev_gray[track_id] = curr_gray
            return {"sigma": 0.0, "is_live": False, "frames": 0}

        prev = self._prev_gray.get(track_id)
        if prev is not None and prev.shape == curr_gray.shape:
            mag = self._farneback_mean_mag(prev, curr_gray)
            self._buffers[track_id].append(mag)

        self._prev_gray[track_id] = curr_gray

        buf = list(self._buffers[track_id])
        sigma = float(np.std(buf)) if len(buf) >= 2 else 0.0
        is_live = self.flow_min < sigma < self.flow_max

        return {
            "sigma": round(sigma, 4),
            "is_live": is_live,
            "frames": len(buf),
        }

    def window_full(self, track_id: str) -> bool:
        """True once we have accumulated window_frames flow measurements."""
        buf = self._buffers.get(track_id)
        return buf is not None and len(buf) >= self.window_frames

    def reset(self, track_id: str) -> None:
        self._buffers.pop(track_id, None)
        self._prev_gray.pop(track_id, None)
