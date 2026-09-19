"""
Layer 2 — Screen / Print Moire Frequency Detector.
Uses 2D FFT ring-energy ratio to detect regular pixel-grid patterns
from LCD/OLED screens and halftone-printed photos.
"""
import cv2
import numpy as np
from ..config import L2_FFT_INNER_R, L2_FFT_OUTER_R, L2_MOIRE_MAX


class MoireDetector:
    """Stateless detector. All methods are pure functions safe to call from any thread."""

    def __init__(self, inner_r: int = L2_FFT_INNER_R, outer_r: int = L2_FFT_OUTER_R,
                 threshold: float = L2_MOIRE_MAX):
        self.inner_r = inner_r
        self.outer_r = outer_r
        self.threshold = threshold

    def score(self, face_bgr: np.ndarray) -> float:
        """
        Returns 0.0 (clean / biological) → 1.0 (strong Moire / screen / print detected).
        Safe to call from any thread — no shared state.
        Uses harmonic peak-to-average ratio in the normalized 2D FFT spectrum.
        Screens emit sharp periodic Dirac spikes, whereas natural faces have smooth distribution.
        """
        if face_bgr is None or face_bgr.size == 0:
            return 0.0
        try:
            h, w = face_bgr.shape[:2]
            if h < 48 or w < 48:
                # Low-resolution face crops cannot reliably resolve high-frequency moiré patterns
                return 0.0

            gray = cv2.cvtColor(face_bgr, cv2.COLOR_BGR2GRAY).astype(np.float32)
            norm = cv2.resize(gray, (128, 128))
            fft = np.abs(np.fft.fftshift(np.fft.fft2(norm)))
            log_fft = np.log1p(fft)

            Y, X = np.ogrid[:128, :128]
            r = np.sqrt((X - 64) ** 2 + (Y - 64) ** 2)

            ring_mask = (r > self.inner_r) & (r < self.outer_r)
            ring_vals = log_fft[ring_mask]
            if len(ring_vals) == 0:
                return 0.0

            peak = float(np.max(ring_vals))
            mean = float(np.mean(ring_vals))
            peak_ratio = peak / (mean + 1e-6)

            # Natural faces have peak_ratio 1.2 - 2.0. Screens/grids have peak_ratio > 3.0.
            return float(np.clip((peak_ratio - 2.2) / 1.5, 0.0, 1.0))
        except Exception:
            return 0.0  # fail-open at this layer; neural layer remains

    def is_spoof(self, face_bgr: np.ndarray) -> bool:
        """Returns True if screen/print artifact is detected above threshold."""
        return self.score(face_bgr) > self.threshold

