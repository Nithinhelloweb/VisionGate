"""
integration.py — Drop-in shim that upgrades evaluate_face_liveness()
to include the 5-layer anti-spoofing pipeline.

Usage in main.py:
  from anti_spoof.integration import run_full_liveness_check

  # Replace calls to evaluate_face_liveness() with:
  result = run_full_liveness_check(img, face, reg_no=reg_no)
"""
from __future__ import annotations

import numpy as np
import cv2
from typing import Optional

from .pipeline import run_antispoof_on_frame
from .decision_gate import Decision


def run_full_liveness_check(
    img: np.ndarray,
    face,
    reg_no: str = "unknown",
    camera_id: str = "cam_0",
    recognition_cosine: float = 0.0,
    existing_liveness_result: Optional[dict] = None,
) -> dict:
    """
    Full 5-layer liveness check. Intended to replace / augment the existing
    evaluate_face_liveness() call in main.py.

    Args:
        img:                    Full BGR frame.
        face:                   InsightFace face object (has .bbox, .kps).
        reg_no:                 Person identifier (for dedup tracking).
        camera_id:              Camera source identifier.
        recognition_cosine:     Cosine similarity already computed by InsightFace.
        existing_liveness_result: Optional result from existing evaluate_face_liveness()
                                  — if provided, we AND it with neural check.

    Returns:
        Dict compatible with evaluate_face_liveness() output:
        {
          "is_live": bool,
          "score":   float,
          "reason":  str,
          "flags":   list,
          "metrics": dict,
        }
    """
    # Extract face ROI
    bbox = None
    face_roi = None
    try:
        if face is not None and hasattr(face, "bbox"):
            bbox_arr = face.bbox.astype(int)
            h, w = img.shape[:2]
            x1 = max(0, int(bbox_arr[0]))
            y1 = max(0, int(bbox_arr[1]))
            x2 = min(w, int(bbox_arr[2]))
            y2 = min(h, int(bbox_arr[3]))
            bbox = [x1, y1, x2, y2]
            if x2 > x1 and y2 > y1:
                face_roi = img[y1:y2, x1:x2]
    except Exception:
        pass

    if bbox is None or face_roi is None or face_roi.size == 0:
        return {
            "is_live": False,
            "score": 0.0,
            "reason": "Could not extract face region for liveness check",
            "flags": ["NO_FACE_ROI"],
            "metrics": {},
        }

    # Run 5-layer pipeline
    try:
        decision, verdict, layer_failed = run_antispoof_on_frame(
            frame_bgr=img,
            bbox=bbox,
            face_roi_bgr=face_roi,
            track_id=str(reg_no),
            session_key=camera_id,
            recognition_cosine=recognition_cosine,
            person_id=reg_no,
            camera_id=camera_id,
        )

        neural_live = (decision == Decision.MARK_ATTENDANCE or
                       decision == Decision.ALREADY_LOGGED or
                       decision == Decision.UNKNOWN_FACE)

        is_live = neural_live

        # If neural ensemble passed with solid confidence (>= 0.78 or 0.70 in low light),
        # only override if physical device bezel/border or injection was detected.
        # Forehead ash/tilak/sheen or low-res LBP noise will not falsely reject live human faces.
        if existing_liveness_result and not existing_liveness_result.get("is_live", True):
            existing_flags = existing_liveness_result.get("flags", [])
            hard_rejection_flags = {"DEVICE_BEZEL_DETECTED", "L5_INJECTION"}
            has_hard_reject = any(f in existing_flags for f in hard_rejection_flags)
            min_override_score = 0.70 if verdict.mean_y < 68.0 else 0.78
            if has_hard_reject or verdict.l1_score_final < min_override_score:
                is_live = False
        else:
            existing_flags = []

        # Build detailed, user-understandable reason
        layer_reasons = {
            "L1_NEURAL": "Neural anti-spoof check failed: Printed photo, synthetic face, or 3D mask detected",
            "LOW_LIGHT": "Low lighting detected: Face features are not clear enough to verify liveness. Please turn on screen flash or move to a well-lit area",
            "L2_MOIRE":  "Screen Moiré pattern detected: Digital display or video replay detected",
            "L3_BLINK":  "No natural blink detected: Static image or photo attack detected",
            "L4_FLOW":   "Unnatural motion pattern detected: Inconsistent facial micro-movement",
            "L5_INJECTION": "Camera authentication failed: Virtual camera or video stream injection detected",
        }

        if not is_live:
            if layer_failed == "LOW_LIGHT" or (layer_failed == "L1_NEURAL" and verdict.mean_y < 68.0):
                reason = layer_reasons["LOW_LIGHT"]
            elif layer_failed in layer_reasons:
                reason = layer_reasons[layer_failed]
            elif existing_liveness_result and existing_liveness_result.get("reason"):
                reason = existing_liveness_result["reason"]
            else:
                reason = "Face liveness verification failed"
        else:
            reason = "Live human face verified"

        flags = []
        if not is_live:
            if layer_failed:
                flags.append(layer_failed)
            if verdict.mean_y < 68.0 and "LOW_LIGHT" not in flags:
                flags.append("LOW_LIGHT")
            flags.extend(existing_flags)

        score = verdict.l1_score_final

        return {
            "is_live": is_live,
            "score": round(score, 3),
            "reason": reason,
            "flags": flags,
            "metrics": {
                "l1_score_v2":  verdict.l1_score_v2,
                "l1_score_se":  verdict.l1_score_se,
                "l1_ensemble":  verdict.l1_score_final,
                "l2_moire":     verdict.l2_moire_score,
                "l3_blink":     verdict.l3_blink_detected,
                "l3_frames":    verdict.l3_frames_seen,
                "l4_flow_sigma": verdict.l4_flow_sigma,
                "l4_frames":    verdict.l4_frames_seen,
                "layers_passed": verdict.layers_passed(),
                "decision":     decision.value,
            },
        }

    except Exception as exc:
        # On any anti-spoof error, fail-CLOSED (reject)
        import traceback
        traceback.print_exc()
        return {
            "is_live": False,
            "score": 0.0,
            "reason": f"Anti-spoofing pipeline error: {exc}",
            "flags": ["PIPELINE_ERROR"],
            "metrics": {},
        }
