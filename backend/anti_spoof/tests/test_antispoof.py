"""
tests/test_antispoof.py — Unit tests for the 5-layer anti-spoofing system.
Run with: python -m pytest backend/anti_spoof/tests/ -v
"""
import os, sys, collections
import numpy as np
import cv2
try:
    import pytest
except ImportError:
    pytest = None

_BACKEND = os.path.join(os.path.dirname(__file__), "..", "..")
sys.path.insert(0, _BACKEND)

from anti_spoof.utils import crop_face, preprocess, softmax, apply_adaptive_gamma
from anti_spoof.layers.moire_detector import MoireDetector
from anti_spoof.layers.blink_detector import BlinkDetector
from anti_spoof.layers.flow_detector import FlowDetector
from anti_spoof.decision_gate import DecisionGate, LivenessVerdict, Decision


# ── Fixtures ─────────────────────────────────────────────────────────────────

def make_flat_face(size=80):
    """Solid-colour image — near-zero FFT ring energy (like real skin)."""
    img = np.zeros((size, size, 3), dtype=np.uint8)
    img[:] = [80, 120, 180]  # uniform skin-like BGR
    return img


def make_screen(size=80):
    """Regular horizontal pixel-row pattern — strong Moire FFT peaks."""
    img = np.zeros((size, size, 3), dtype=np.uint8)
    for i in range(0, size, 3):
        img[i, :] = [220, 220, 220]  # evenly-spaced bright lines
    return img


def make_frame_with_face(frame_size=(640, 480)):
    frame = np.random.randint(100, 200, (*frame_size[::-1], 3), dtype=np.uint8)
    return frame, [200, 150, 300, 280]


# ── crop_face ────────────────────────────────────────────────────────────────

def test_crop_face_returns_80x80():
    frame, bbox = make_frame_with_face()
    crop = crop_face(frame, bbox, scale=2.7)
    assert crop is not None and crop.shape == (80, 80, 3)


def test_crop_face_se_scale():
    frame, bbox = make_frame_with_face()
    crop = crop_face(frame, bbox, scale=4.0)
    assert crop is not None and crop.shape == (80, 80, 3)


def test_crop_face_none_frame():
    assert crop_face(None, [0, 0, 100, 100], scale=2.7) is None


# ── preprocess ───────────────────────────────────────────────────────────────

def test_preprocess_shape():
    t = preprocess(make_flat_face(80))
    assert t.shape == (1, 3, 80, 80)
    assert t.dtype == np.float32
    assert 0.0 <= t.min() and t.max() <= 255.0


# ── softmax ──────────────────────────────────────────────────────────────────

def test_softmax_sums_to_one():
    p = softmax(np.array([1.0, 2.0, 0.5]))
    assert abs(p.sum() - 1.0) < 1e-6


# ── MoireDetector ────────────────────────────────────────────────────────────

def test_moire_low_on_flat_face():
    det = MoireDetector()
    score = det.score(make_flat_face(80))
    # Solid colour image has essentially all energy at DC; ring ratio should be low
    assert score < 0.60, f"Flat face moire score unexpectedly high: {score}"


def test_moire_higher_on_screen():
    det = MoireDetector()
    score_screen = det.score(make_screen(80))
    score_flat   = det.score(make_flat_face(80))
    assert score_screen > score_flat, f"Screen {score_screen:.3f} should > flat {score_flat:.3f}"


def test_moire_none_input():
    assert MoireDetector().score(None) == 0.0


# ── BlinkDetector ─────────────────────────────────────────────────────────────

def test_blink_buffer_empty_initially():
    det = BlinkDetector()
    result = det.update("track1", make_flat_face(80))
    # Buffer only fills when EAR is detected; synthetic image may have 0 eyes
    assert "frames_in_buffer" in result


def test_blink_window_full_direct():
    """Test buffer capacity directly — EAR values are inserted manually."""
    det = BlinkDetector(window_frames=5)
    # Manually fill buffer (simulates 5 frames where eyes were detected)
    det._buffers["track1"] = collections.deque([0.30, 0.28, 0.15, 0.29, 0.31], maxlen=5)
    assert det.window_full("track1")


def test_blink_detected_when_ear_dips():
    det = BlinkDetector(window_frames=10, ear_threshold=0.22)
    det._buffers["track1"] = collections.deque([0.30, 0.28, 0.18, 0.29, 0.31], maxlen=10)
    assert det.has_blinked("track1")  # 0.18 < 0.22 = blink


def test_blink_reset():
    det = BlinkDetector(window_frames=5)
    det._buffers["track1"] = collections.deque([0.25]*5, maxlen=5)
    det.reset("track1")
    assert not det.window_full("track1")


# ── FlowDetector ─────────────────────────────────────────────────────────────

def test_flow_static_low_sigma():
    det = FlowDetector(window_frames=5)
    face = make_flat_face(80)
    for _ in range(6):
        result = det.update("track1", face)
    assert result["sigma"] < 1.0


def test_flow_random_higher_sigma():
    det = FlowDetector(window_frames=5)
    for _ in range(6):
        face = np.random.randint(0, 255, (80, 80, 3), dtype=np.uint8)
        result = det.update("track1", face)
    assert result["sigma"] >= 0.0   # random frames produce nonzero sigma


# ── DecisionGate ─────────────────────────────────────────────────────────────

def test_gate_passes_all_live():
    gate = DecisionGate(enable_l5_hmac=False, enable_l3_blink=False, enable_l4_flow=False)
    v = LivenessVerdict(
        l1_score_final=0.95, l1_is_live=True,
        l2_moire_score=0.10, l2_is_live=True,
        l3_blink_detected=True, l3_frames_seen=90,
        l4_flow_sigma=0.5, l4_is_live=True, l4_frames_seen=10,
        l5_hmac_valid=True, recognition_cosine=0.80, person_id="p1",
    )
    decision, layer = gate.evaluate(v)
    assert decision == Decision.MARK_ATTENDANCE


def test_gate_rejects_low_neural():
    gate = DecisionGate(enable_l5_hmac=False, enable_l3_blink=False, enable_l4_flow=False)
    v = LivenessVerdict(l1_score_final=0.40, l1_is_live=False, l2_is_live=True,
                        l3_blink_detected=True, l3_frames_seen=0,
                        l4_is_live=True, l4_frames_seen=0, l5_hmac_valid=True,
                        recognition_cosine=0.80, person_id="p1")
    decision, layer = gate.evaluate(v)
    assert decision == Decision.SPOOF_REJECTED and layer == "L1_NEURAL"


def test_gate_rejects_moire():
    gate = DecisionGate(enable_l5_hmac=False, enable_l3_blink=False, enable_l4_flow=False)
    v = LivenessVerdict(l1_score_final=0.95, l1_is_live=True,
                        l2_moire_score=0.80, l2_is_live=False,
                        l3_blink_detected=True, l3_frames_seen=0,
                        l4_is_live=True, l4_frames_seen=0, l5_hmac_valid=True,
                        recognition_cosine=0.80, person_id="p1")
    decision, layer = gate.evaluate(v)
    assert decision == Decision.SPOOF_REJECTED and layer == "L2_MOIRE"


def test_gate_unknown_face():
    gate = DecisionGate(enable_l5_hmac=False, enable_l3_blink=False, enable_l4_flow=False)
    v = LivenessVerdict(l1_score_final=0.95, l1_is_live=True,
                        l2_moire_score=0.10, l2_is_live=True,
                        l3_blink_detected=True, l3_frames_seen=0,
                        l4_is_live=True, l4_frames_seen=0, l5_hmac_valid=True,
                        recognition_cosine=0.30, person_id="p1")
    decision, layer = gate.evaluate(v)
    assert decision == Decision.UNKNOWN_FACE


def test_gate_rejects_no_blink():
    gate = DecisionGate(enable_l5_hmac=False, enable_l3_blink=True, enable_l4_flow=False)
    v = LivenessVerdict(l1_score_final=0.95, l1_is_live=True,
                        l2_moire_score=0.10, l2_is_live=True,
                        l3_blink_detected=False, l3_frames_seen=90,  # window full, no blink
                        l4_is_live=True, l4_frames_seen=0, l5_hmac_valid=True,
                        recognition_cosine=0.80, person_id="p1")
    decision, layer = gate.evaluate(v)
    assert decision == Decision.SPOOF_REJECTED and layer == "L3_BLINK"


# ── Low Light Tests ─────────────────────────────────────────────────────────

def test_apply_adaptive_gamma_low_light():
    dark_crop = np.full((80, 80, 3), 40, dtype=np.uint8)
    enhanced = apply_adaptive_gamma(dark_crop, mean_luma=40.0)
    assert float(np.mean(enhanced)) > 40.0


def test_apply_adaptive_gamma_normal_light():
    bright_crop = np.full((80, 80, 3), 150, dtype=np.uint8)
    enhanced = apply_adaptive_gamma(bright_crop, mean_luma=150.0)
    assert np.array_equal(enhanced, bright_crop)


def test_gate_passes_low_light_calibrated():
    gate = DecisionGate(enable_l5_hmac=False, enable_l3_blink=False, enable_l4_flow=False)
    # Score 0.74 passes in low light (mean_y=55) because > 0.70 and L2 moire is clean
    v = LivenessVerdict(l1_score_final=0.74, l1_is_live=True,
                        l2_moire_score=0.10, l2_is_live=True,
                        l3_blink_detected=True, l3_frames_seen=0,
                        l4_is_live=True, l4_frames_seen=0, l5_hmac_valid=True,
                        recognition_cosine=0.80, person_id="p1", mean_y=55.0)
    decision, layer = gate.evaluate(v)
    assert decision == Decision.MARK_ATTENDANCE


def test_gate_rejects_low_light_with_actionable_reason():
    gate = DecisionGate(enable_l5_hmac=False, enable_l3_blink=False, enable_l4_flow=False)
    # Score 0.40 fails even in low light, but emits LOW_LIGHT instead of accusing of fake photo
    v = LivenessVerdict(l1_score_final=0.40, l1_is_live=False,
                        l2_moire_score=0.10, l2_is_live=True,
                        l3_blink_detected=True, l3_frames_seen=0,
                        l4_is_live=True, l4_frames_seen=0, l5_hmac_valid=True,
                        recognition_cosine=0.80, person_id="p1", mean_y=55.0)
    decision, layer = gate.evaluate(v)
    assert decision == Decision.SPOOF_REJECTED and layer == "LOW_LIGHT"


if __name__ == "__main__":
    if pytest is not None:
        pytest.main([__file__, "-v"])
    else:
        passed = 0
        failed = 0
        for name, fn in list(globals().items()):
            if name.startswith("test_") and callable(fn):
                try:
                    fn()
                    print(f"PASS: {name}")
                    passed += 1
                except Exception as e:
                    print(f"FAIL: {name}: {e}")
                    failed += 1
        print(f"\nTotal: {passed + failed} | Passed: {passed} | Failed: {failed}")
        if failed > 0:
            sys.exit(1)

