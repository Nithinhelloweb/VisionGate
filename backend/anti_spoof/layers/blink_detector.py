"""
Layer 3 — Passive Blink Liveness Detector (EAR via OpenCV Haar landmarks).

Uses OpenCV eye detection (no mediapipe dependency) to compute a blink signal
passively over a rolling frame buffer keyed by track_id.
Real faces blink every 3-5 seconds. Static photos/masks never blink.
"""
import cv2
import numpy as np
from collections import deque
from typing import Dict, Optional
from ..config import L3_EAR_BLINK_THRESHOLD, L3_WINDOW_FRAMES


class BlinkDetector:
    """
    Stateful detector. One instance per pipeline worker.
    Thread-UNSAFE — use one instance per thread or wrap with a lock.
    """

    def __init__(
        self,
        ear_threshold: float = L3_EAR_BLINK_THRESHOLD,
        window_frames: int = L3_WINDOW_FRAMES,
    ):
        self.ear_threshold = ear_threshold
        self.window_frames = window_frames
        # track_id → deque of (ear_left, ear_right) tuples
        self._buffers: Dict[str, deque] = {}
        # Load eye cascades
        self._eye_cascade = cv2.CascadeClassifier(
            cv2.data.haarcascades + "haarcascade_eye.xml"
        )
        self._eye_tree = cv2.CascadeClassifier(
            cv2.data.haarcascades + "haarcascade_eye_tree_eyeglasses.xml"
        )

    def _detect_eye_aspect_ratio(self, face_roi_gray: np.ndarray) -> Optional[float]:
        """
        Estimate EAR-equivalent from eye region height/width ratio.
        Returns None if no eyes detected.
        """
        if face_roi_gray is None or face_roi_gray.size == 0:
            return None
        h, w = face_roi_gray.shape[:2]
        # Look for eyes in top-60% of face roi
        roi = face_roi_gray[: int(h * 0.60), :]
        eyes = self._eye_cascade.detectMultiScale(roi, 1.1, 4, minSize=(15, 8))
        if len(eyes) == 0:
            eyes = self._eye_tree.detectMultiScale(roi, 1.1, 4, minSize=(15, 8))
        if len(eyes) == 0:
            return None
        # Average EAR proxy: eye height / eye width for all detected eyes
        ears = []
        for (ex, ey, ew, eh) in eyes:
            ear = eh / (ew + 1e-6)
            ears.append(ear)
        return float(np.mean(ears))

    def update(self, track_id: str, face_bgr: np.ndarray) -> dict:
        """
        Process one frame for a given track.
        Returns:
          { "ear": float|None, "blink_detected": bool, "frames_in_buffer": int }
        """
        if track_id not in self._buffers:
            self._buffers[track_id] = deque(maxlen=self.window_frames)

        gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY) if face_bgr is not None else None
        ear = self._detect_eye_aspect_ratio(gray)
        if ear is not None:
            self._buffers[track_id].append(ear)

        buf = self._buffers[track_id]
        # A blink is a dip below threshold in the rolling window
        blink_detected = any(e < self.ear_threshold for e in buf) if buf else False

        return {
            "ear": round(ear, 3) if ear is not None else None,
            "blink_detected": blink_detected,
            "frames_in_buffer": len(buf),
        }

    def has_blinked(self, track_id: str) -> bool:
        """True if at least one blink was observed in the current window."""
        buf = self._buffers.get(track_id)
        if not buf:
            return False
        return any(e < self.ear_threshold for e in buf)

    def window_full(self, track_id: str) -> bool:
        """True once we have seen window_frames frames for this track."""
        buf = self._buffers.get(track_id)
        return buf is not None and len(buf) >= self.window_frames

    def reset(self, track_id: str) -> None:
        """Clear history for a track (e.g., after successful mark)."""
        self._buffers.pop(track_id, None)
