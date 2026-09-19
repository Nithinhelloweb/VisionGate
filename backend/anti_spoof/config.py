"""
Anti-Spoof Config — All thresholds, model paths, and SHA-256 checksums.
Never hardcode values outside this file.
"""
import os

# ── Base paths ──────────────────────────────────────────────────────────────
_HERE = os.path.dirname(os.path.abspath(__file__))
_BACKEND = os.path.dirname(_HERE)
MODEL_DIR = os.path.join(_BACKEND, "resources", "anti_spoof_models")

# ── Model files ─────────────────────────────────────────────────────────────
MODEL_V2 = os.path.join(MODEL_DIR, "2.7_80x80_MiniFASNetV2.onnx")
MODEL_SE = os.path.join(MODEL_DIR, "4_0_0_80x80_MiniFASNetV1SE.onnx")

# Crop scales must match model training (parsed from filename prefix)
CROP_SCALE_V2 = 2.7
CROP_SCALE_SE = 4.0

# ── Layer 1 — Neural Ensemble thresholds ────────────────────────────────────
L1_LIVE_THRESHOLD = 0.80          # calibrated geometric mean score to pass as live (fakes score < 0.06)
L1_LOW_LIGHT_THRESHOLD = 0.70     # calibrated threshold when face crop is in low light and other layers pass
LOW_LIGHT_LUMA_CUTOFF = 78.0      # average face luminance below which scene is classified as low light
L1_INPUT_SIZE = (80, 80)          # both models use 80×80 BGR input
L1_LIVE_CLASS_INDEX = 1           # softmax index for "real" class (0: 2D attack, 1: real, 2: 3D/screen)

# ── Layer 2 — Moire / Screen Frequency ──────────────────────────────────────
L2_MOIRE_MAX = 0.50               # moire_score > this → spoof (screens score > 0.70, real faces score ~0.0)
L2_FFT_INNER_R = 16               # inner radius of detection ring (px on 128x128 normalized spectrum)
L2_FFT_OUTER_R = 55               # outer radius of detection ring (px on 128x128 normalized spectrum)
MIN_FACE_RESOLUTION_PIXELS = 45   # minimum face crop dimension (w or h) for full frequency checks

# ── Layer 3 — Passive Blink (EAR) ───────────────────────────────────────────
L3_EAR_BLINK_THRESHOLD = 0.22     # EAR below this = blink detected
L3_WINDOW_FRAMES = 90             # frames before declaring no-blink spoof
L3_BLINK_REQUIRED = True          # set False in high-throughput low-security

# ── Layer 4 — Optical Flow temporal consistency ──────────────────────────────
L4_FLOW_MIN_SIGMA = 0.06          # below = static (photo / rigid mask)
L4_FLOW_MAX_SIGMA = 9.0           # above = violent shake (tamper)
L4_FLOW_WINDOW_FRAMES = 10        # frames in rolling buffer

# ── Layer 5 — Camera Trust (HMAC) ───────────────────────────────────────────
L5_HMAC_ALGORITHM = "sha256"
L5_BYTES_TO_SIGN = 2048           # first N bytes of frame JPEG for signing

# ── Decision Gate ────────────────────────────────────────────────────────────
RECOG_THRESHOLD = 0.68            # InsightFace cosine similarity
DEDUP_WINDOW_SEC = 300            # cooldown between marks for same person

# ── SHA-256 checksums ────────────────────────────────────────────────────────
EXPECTED_HASH_V2 = "F88F54EE8C4B3BE2F6099311F0575664CD709D34B35562FB6712F39F165207E6"
EXPECTED_HASH_SE = "DD69FCA671E8252DD122BD85283480F0704005DCAF2ECC1F579734540616268C"
VERIFY_MODEL_HASHES = True        # enforces cryptographic integrity on cold start

# ── ONNX execution providers (ordered by preference) ────────────────────────
# Auto-detect: use GPU providers if available, fall back to CPU.
def _build_providers() -> list:
    try:
        import os
        # Ensure PyTorch CUDA DLLs (e.g. cublasLt64_12.dll) are accessible to ONNX Runtime on Windows
        try:
            import torch
            torch_lib = os.path.join(os.path.dirname(torch.__file__), "lib")
            if os.path.exists(torch_lib):
                if hasattr(os, "add_dll_directory"):
                    try:
                        os.add_dll_directory(torch_lib)
                    except Exception:
                        pass
                if torch_lib not in os.environ.get("PATH", ""):
                    os.environ["PATH"] = torch_lib + os.pathsep + os.environ.get("PATH", "")
        except ImportError:
            pass

        import onnxruntime as _ort
        available = _ort.get_available_providers()
        # TensorRT requires separate standalone NVIDIA TensorRT 10.x binaries (nvinfer_10.dll)
        # on system PATH. We prioritize CUDA and DirectML to avoid DLL lookup errors.
        prefs = []
        if os.getenv("ENABLE_TENSORRT", "").lower() in ("1", "true"):
            prefs.append("TensorrtExecutionProvider")
        prefs.extend(["CUDAExecutionProvider", "DmlExecutionProvider"])
        chosen = [p for p in prefs if p in available]
        chosen.append("CPUExecutionProvider")
        return chosen
    except Exception:
        return ["CPUExecutionProvider"]

ONNX_PROVIDERS = _build_providers()

