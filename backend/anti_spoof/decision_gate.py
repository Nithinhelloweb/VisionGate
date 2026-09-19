"""
decision_gate.py — 5-Layer liveness decision engine.

All 5 layers must pass for attendance to be marked.
Each rejection is logged to the spoof_events table.
"""
from __future__ import annotations

import time
import hashlib
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, Optional


class Decision(str, Enum):
    MARK_ATTENDANCE = "MARK_ATTENDANCE"
    SPOOF_REJECTED  = "SPOOF_REJECTED"
    INJECT_REJECTED = "INJECT_REJECTED"
    UNKNOWN_FACE    = "UNKNOWN_FACE"
    ALREADY_LOGGED  = "ALREADY_LOGGED"
    INSUFFICIENT_DATA = "INSUFFICIENT_DATA"


@dataclass
class LivenessVerdict:
    # Layer 1 — Neural Ensemble
    l1_score_v2: float = 0.0
    l1_score_se: float = 0.0
    l1_score_final: float = 0.0
    l1_is_live: bool = False

    # Layer 2 — FFT Moire
    l2_moire_score: float = 0.0
    l2_is_live: bool = True   # default True (fail-open on missing data)

    # Layer 3 — Blink EAR
    l3_blink_detected: bool = False
    l3_frames_seen: int = 0

    # Layer 4 — Optical Flow
    l4_flow_sigma: float = 0.0
    l4_is_live: bool = False
    l4_frames_seen: int = 0

    # Layer 5 — Camera Trust
    l5_hmac_valid: bool = True   # True if trust checking is disabled

    # Recognition
    recognition_cosine: float = 0.0
    person_id: Optional[str] = None

    # Metadata
    mean_y: float = 128.0
    camera_id: str = ""
    track_id: str = ""
    frame_ts: datetime = field(default_factory=datetime.now)

    def layers_passed(self) -> dict:
        return {
            "L1_neural": self.l1_is_live,
            "L2_moire":  self.l2_is_live,
            "L3_blink":  self.l3_blink_detected,
            "L4_flow":   self.l4_is_live,
            "L5_trust":  self.l5_hmac_valid,
        }


from .config import (
    L1_LIVE_THRESHOLD,
    L1_LOW_LIGHT_THRESHOLD,
    LOW_LIGHT_LUMA_CUTOFF,
    L2_MOIRE_MAX,
    L4_FLOW_MIN_SIGMA,
    L4_FLOW_MAX_SIGMA,
    RECOG_THRESHOLD,
    DEDUP_WINDOW_SEC,
)


class DecisionGate:
    """
    Evaluates all 5 anti-spoofing layers and emits a Decision.
    Stateful only for the dedup cache — everything else is pure.
    """

    # Thresholds from config.py
    L1_THRESHOLD     = L1_LIVE_THRESHOLD
    L1_LOW_LIGHT     = L1_LOW_LIGHT_THRESHOLD
    LOW_LIGHT_LUMA   = LOW_LIGHT_LUMA_CUTOFF
    L2_MAX_MOIRE     = L2_MOIRE_MAX
    L4_FLOW_MIN      = L4_FLOW_MIN_SIGMA
    L4_FLOW_MAX      = L4_FLOW_MAX_SIGMA
    RECOG_THRESHOLD  = RECOG_THRESHOLD
    DEDUP_WINDOW_SEC = DEDUP_WINDOW_SEC
    MIN_FLOW_FRAMES  = 5    # need at least N frames before trusting flow
    MIN_BLINK_FRAMES = 30   # need at least N frames before declaring no-blink

    def __init__(self, enable_l5_hmac: bool = False, enable_l3_blink: bool = True,
                 enable_l4_flow: bool = True):
        # Dedup: person_id -> last_mark_timestamp
        self._dedup_cache: Dict[str, float] = {}
        self.enable_l5_hmac = enable_l5_hmac
        self.enable_l3_blink = enable_l3_blink
        self.enable_l4_flow = enable_l4_flow

    def evaluate(self, v: LivenessVerdict) -> tuple[Decision, str]:
        """
        Evaluate all layers in order.
        Returns (Decision, layer_failed_name).
        """
        # ── Layer 5: Camera trust ──────────────────────────────────────────
        if self.enable_l5_hmac and not v.l5_hmac_valid:
            return Decision.INJECT_REJECTED, "L5_INJECTION"

        # ── Layer 1: Neural ensemble ───────────────────────────────────────
        # In low lighting, camera high-ISO noise flattens 3D specular curvature.
        # If mean_y is low AND other layers pass cleanly (no screen moire),
        # calibrate the threshold to L1_LOW_LIGHT (0.70).
        is_low_light = v.mean_y < self.LOW_LIGHT_LUMA
        active_l1_threshold = (
            self.L1_LOW_LIGHT
            if (is_low_light and v.l2_is_live and v.l2_moire_score < 0.35)
            else self.L1_THRESHOLD
        )

        if v.l1_score_final < active_l1_threshold:
            if is_low_light:
                return Decision.SPOOF_REJECTED, "LOW_LIGHT"
            return Decision.SPOOF_REJECTED, "L1_NEURAL"

        # ── Layer 2: Moire / screen frequency ─────────────────────────────
        if not v.l2_is_live:
            return Decision.SPOOF_REJECTED, "L2_MOIRE"

        # ── Layer 3: Blink detection ───────────────────────────────────────
        if self.enable_l3_blink and v.l3_frames_seen >= self.MIN_BLINK_FRAMES:
            if not v.l3_blink_detected:
                return Decision.SPOOF_REJECTED, "L3_BLINK"

        # ── Layer 4: Optical flow ──────────────────────────────────────────
        if self.enable_l4_flow and v.l4_frames_seen >= self.MIN_FLOW_FRAMES:
            # If neural ensemble strongly confirms live (>= 0.88), allow subtle natural stillness
            if not v.l4_is_live and v.l1_score_final < 0.88:
                return Decision.SPOOF_REJECTED, "L4_FLOW"

        # ── Recognition ───────────────────────────────────────────────────
        if v.recognition_cosine < self.RECOG_THRESHOLD:
            return Decision.UNKNOWN_FACE, ""

        # ── Dedup ─────────────────────────────────────────────────────────
        if v.person_id and self._is_duplicate(v.person_id):
            return Decision.ALREADY_LOGGED, ""

        # ── All clear ─────────────────────────────────────────────────────
        if v.person_id:
            self._dedup_cache[v.person_id] = time.time()
        return Decision.MARK_ATTENDANCE, ""

    def _is_duplicate(self, person_id: str) -> bool:
        last = self._dedup_cache.get(person_id)
        if last is None:
            return False
        return (time.time() - last) < self.DEDUP_WINDOW_SEC

    def build_audit_payload(self, v: LivenessVerdict, decision: Decision, layer_failed: str) -> dict:
        """Build the dict to insert into spoof_events table."""
        return {
            "camera_id":    v.camera_id,
            "track_id":     v.track_id,
            "frame_ts":     v.frame_ts.isoformat(),
            "layer_failed": layer_failed,
            "l1_score":     v.l1_score_final,
            "l2_score":     v.l2_moire_score,
            "l3_blink":     v.l3_blink_detected,
            "l4_sigma":     v.l4_flow_sigma,
            "decision":     decision.value,
            "layers":       v.layers_passed(),
        }
