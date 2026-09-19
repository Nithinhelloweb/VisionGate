"""
pipeline.py — Full 5-layer anti-spoofing pipeline for per-request use.

This is the HIGH-LEVEL integration point called by the attendance endpoint.
For each incoming face image:
  1. Run neural ensemble (L1)
  2. Run FFT moire check (L2)
  3. Update blink detector (L3) — needs track_id for stateful buffer
  4. Update optical flow detector (L4) — needs track_id + rolling frames
  5. Validate camera trust (L5) — optional
  6. Evaluate decision gate
"""
from __future__ import annotations

import numpy as np
from datetime import datetime
from typing import Optional

from .ensemble import EnsemblePredictor
from .layers.moire_detector import MoireDetector
from .layers.blink_detector import BlinkDetector
from .layers.flow_detector import FlowDetector
from .layers.trust_validator import TrustValidator
from .decision_gate import DecisionGate, LivenessVerdict, Decision
from .config import (
    L1_LIVE_THRESHOLD,
    L1_LOW_LIGHT_THRESHOLD,
    LOW_LIGHT_LUMA_CUTOFF,
    L2_MOIRE_MAX,
    L3_BLINK_REQUIRED,
    L4_FLOW_MIN_SIGMA,
    L4_FLOW_MAX_SIGMA,
    RECOG_THRESHOLD,
)


# Module-level singletons — shared safely: ensemble is thread-safe,
# stateful detectors are NOT shared (each request creates its own or
# re-uses per-session instances managed externally)
_ensemble = EnsemblePredictor()
_gate = DecisionGate(enable_l5_hmac=False, enable_l3_blink=True, enable_l4_flow=True)
_moire = MoireDetector()

# Per-session stateful detectors — keyed by session/camera ID
_blink_detectors: dict = {}
_flow_detectors: dict = {}


def get_or_create_detectors(session_key: str):
    """Return (BlinkDetector, FlowDetector) for a session — creates on first call."""
    if session_key not in _blink_detectors:
        _blink_detectors[session_key] = BlinkDetector()
    if session_key not in _flow_detectors:
        _flow_detectors[session_key] = FlowDetector()
    return _blink_detectors[session_key], _flow_detectors[session_key]


def run_antispoof_on_frame(
    frame_bgr: np.ndarray,
    bbox,
    face_roi_bgr: np.ndarray,
    track_id: str = "default",
    session_key: str = "default",
    recognition_cosine: float = 0.0,
    person_id: Optional[str] = None,
    camera_id: str = "cam_0",
) -> tuple[Decision, LivenessVerdict, str]:
    """
    Run full 5-layer anti-spoofing pipeline on a single face.

    Args:
        frame_bgr:         Full camera frame (for L1 crop).
        bbox:              Face bounding box [x1, y1, x2, y2].
        face_roi_bgr:      Already-cropped face region (for L2, L3, L4).
        track_id:          Tracker ID for stateful L3/L4 buffers.
        session_key:       Key for blink/flow detector instance (e.g., camera_id).
        recognition_cosine: Cosine similarity from InsightFace (0-1).
        person_id:         Matched person identifier (reg_no etc).
        camera_id:         Camera identifier string.

    Returns:
        (Decision, LivenessVerdict, layer_failed)
    """
    blink_det, flow_det = get_or_create_detectors(session_key)
    now = datetime.now()

    # ── Layer 1: Neural ensemble ───────────────────────────────────────────
    l1_result = _ensemble.predict(frame_bgr, bbox)

    # ── Layer 2: Moire / screen frequency ─────────────────────────────────
    l2_score = _moire.score(face_roi_bgr)
    l2_is_live = l2_score < L2_MOIRE_MAX

    # ── Layer 3: Passive blink ─────────────────────────────────────────────
    l3_result = blink_det.update(track_id, face_roi_bgr)

    # ── Layer 4: Optical flow ──────────────────────────────────────────────
    l4_result = flow_det.update(track_id, face_roi_bgr)

    # ── Luminance computation ──────────────────────────────────────────────
    mean_y = l1_result.get("mean_luma", 128.0)
    if face_roi_bgr is not None and face_roi_bgr.size > 0:
        import cv2
        gray_roi = cv2.cvtColor(face_roi_bgr, cv2.COLOR_BGR2GRAY)
        mean_y = float(np.mean(gray_roi))
    effective_l1_req = L1_LOW_LIGHT_THRESHOLD if mean_y < LOW_LIGHT_LUMA_CUTOFF else L1_LIVE_THRESHOLD
    verdict = LivenessVerdict(
        l1_score_v2=l1_result["score_v2"],
        l1_score_se=l1_result["score_se"],
        l1_score_final=l1_result["score_final"],
        l1_is_live=l1_result["score_final"] >= effective_l1_req,
        l2_moire_score=l2_score,
        l2_is_live=l2_is_live,
        l3_blink_detected=l3_result["blink_detected"],
        l3_frames_seen=l3_result["frames_in_buffer"],
        l4_flow_sigma=l4_result["sigma"],
        l4_is_live=l4_result["is_live"],
        l4_frames_seen=l4_result["frames"],
        l5_hmac_valid=True,
        recognition_cosine=recognition_cosine,
        person_id=person_id,
        mean_y=round(mean_y, 1),
        camera_id=camera_id,
        track_id=track_id,
        frame_ts=now,
    )

    # ── Decision gate ──────────────────────────────────────────────────────
    decision, layer_failed = _gate.evaluate(verdict)
    return decision, verdict, layer_failed


def reset_track(session_key: str, track_id: str) -> None:
    """Clear stateful buffers for a track after successful mark or timeout."""
    blink_det, flow_det = get_or_create_detectors(session_key)
    blink_det.reset(track_id)
    flow_det.reset(track_id)
