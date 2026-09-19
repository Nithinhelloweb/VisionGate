"""
attack_sim.py -- Automated attack simulation test battery.
Simulates all 5 attack vectors and verifies that the Anti-Spoofing pipeline
catches and rejects each vector with the expected layer attribution.

Usage:
    python backend/anti_spoof/tests/attack_sim.py
"""
import sys
import os
import cv2
import numpy as np

# Ensure backend root is on sys.path
_BACKEND = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if _BACKEND not in sys.path:
    sys.path.insert(0, _BACKEND)

from anti_spoof.pipeline import run_antispoof_on_frame
from anti_spoof.decision_gate import Decision


def run_attack_battery():
    print("=" * 70)
    print("VisionGate Anti-Spoofing -- 5-Layer Attack Simulation Battery")
    print("=" * 70)
    
    passed_tests = 0
    total_tests = 0

    # -------------------------------------------------------------
    # Attack 1: Pure Flat / Printed Photo Simulation (Static noise)
    # -------------------------------------------------------------
    total_tests += 1
    print("\n[Test 1] Simulating Photo Print Attack (Flat paper texture)...")
    frame = np.ones((480, 640, 3), dtype=np.uint8) * 120
    # Add printed face rectangle
    frame[140:340, 220:420] = [100, 130, 170]
    bbox = [220, 140, 420, 340]
    face_roi = frame[140:340, 220:420]

    dec, verdict, layer = run_antispoof_on_frame(
        frame_bgr=frame, bbox=bbox, face_roi_bgr=face_roi,
        track_id="attack_print_1", session_key="sim_cam",
        recognition_cosine=0.75, person_id="STF001", camera_id="sim_cam"
    )

    print(f"   Verdict: {dec.value} | Layer Failed: {layer} | Neural Score: {verdict.l1_score_final:.4f}")
    if dec == Decision.SPOOF_REJECTED and layer in ("L1_NEURAL", "L2_MOIRE", "L3_BLINK", "L4_FLOW"):
        print("   [PASS]: Print attack successfully blocked!")
        passed_tests += 1
    else:
        print("   [FAIL]: Print attack was not rejected.")

    # -------------------------------------------------------------
    # Attack 2: Digital Screen Replay Attack (High-frequency Moiré grid)
    # -------------------------------------------------------------
    total_tests += 1
    print("\n[Test 2] Simulating Digital Screen Replay Attack (Moiré pattern)...")
    screen_frame = np.ones((480, 640, 3), dtype=np.uint8) * 100
    for y in range(140, 340, 3):
        screen_frame[y, 220:420] = [240, 240, 240]
    bbox = [220, 140, 420, 340]
    face_roi = screen_frame[140:340, 220:420]

    dec, verdict, layer = run_antispoof_on_frame(
        frame_bgr=screen_frame, bbox=bbox, face_roi_bgr=face_roi,
        track_id="attack_screen_1", session_key="sim_cam",
        recognition_cosine=0.75, person_id="STF001", camera_id="sim_cam"
    )

    print(f"   Verdict: {dec.value} | Layer Failed: {layer} | Moire Score: {verdict.l2_moire_score:.4f}")
    if dec == Decision.SPOOF_REJECTED and (layer == "L2_MOIRE" or layer == "L1_NEURAL"):
        print("   [PASS]: Screen replay attack successfully blocked!")
        passed_tests += 1
    else:
        print("   [FAIL]: Screen replay was not rejected.")

    # -------------------------------------------------------------
    # Attack 3: Static Mask / Repeated Frame (Zero temporal flow)
    # -------------------------------------------------------------
    total_tests += 1
    print("\n[Test 3] Simulating Static Rigid Mask Attack (No temporal micro-tremor)...")
    from anti_spoof.layers.flow_detector import FlowDetector
    fd = FlowDetector(window_frames=6)
    static_roi = np.ones((80, 80, 3), dtype=np.uint8) * 150
    res = {}
    for _ in range(8):
        res = fd.update("rigid_mask", static_roi)
    
    print(f"   Flow Sigma: {res.get('sigma')} (Allowed biological range: 0.06 - 9.0)")
    if not res.get("is_live", False):
        print("   [PASS]: Zero-motion static attack detected as non-biological!")
        passed_tests += 1
    else:
        print("   [FAIL]: Static mask motion was accepted.")

    # -------------------------------------------------------------
    # Attack 4: Non-blinking Staring Attack (Zero blinks over 90 frames)
    # -------------------------------------------------------------
    total_tests += 1
    print("\n[Test 4] Simulating Non-blinking Static Face (No blink across 90 frames)...")
    from anti_spoof.decision_gate import DecisionGate, LivenessVerdict
    gate = DecisionGate(enable_l3_blink=True, enable_l4_flow=False)
    v_noblink = LivenessVerdict(
        l1_score_final=0.95, l1_is_live=True,
        l2_is_live=True,
        l3_blink_detected=False, l3_frames_seen=95,  # Window full, 0 blinks
        l4_is_live=True,
        l5_hmac_valid=True,
        recognition_cosine=0.80, person_id="STF001"
    )
    dec, layer = gate.evaluate(v_noblink)
    print(f"   Decision: {dec.value} | Layer: {layer}")
    if dec == Decision.SPOOF_REJECTED and layer == "L3_BLINK":
        print("   [PASS]: Non-blinking static attack blocked at Layer 3!")
        passed_tests += 1
    else:
        print("   [FAIL]: Non-blinking face was not blocked.")

    # -------------------------------------------------------------
    # Attack 5: Rogue Camera Feed / Virtual Cam Injection (Layer 5)
    # -------------------------------------------------------------
    total_tests += 1
    print("\n[Test 5] Simulating Virtual Camera Injection Attack (Invalid HMAC)...")
    gate_l5 = DecisionGate(enable_l5_hmac=True, enable_l3_blink=False, enable_l4_flow=False)
    v_inject = LivenessVerdict(
        l1_score_final=0.95, l1_is_live=True,
        l2_is_live=True,
        l3_blink_detected=True,
        l4_is_live=True,
        l5_hmac_valid=False,  # Rogue virtual feed without valid hardware key
        recognition_cosine=0.80, person_id="STF001"
    )
    dec, layer = gate_l5.evaluate(v_inject)
    print(f"   Decision: {dec.value} | Layer: {layer}")
    if dec == Decision.INJECT_REJECTED and layer == "L5_INJECTION":
        print("   [PASS]: Virtual camera injection blocked at Layer 5!")
        passed_tests += 1
    else:
        print("   [FAIL]: Injection attack was not rejected.")

    # -------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------
    print("\n" + "=" * 70)
    print(f"Attack Simulation Battery: {passed_tests}/{total_tests} attack vectors BLOCKED.")
    print("=" * 70)
    return passed_tests == total_tests


if __name__ == "__main__":
    success = run_attack_battery()
    sys.exit(0 if success else 1)

