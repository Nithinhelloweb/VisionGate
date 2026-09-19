"""
model.py — Thread-local ONNX session manager for MiniFASNetV2 / V2-SE.
Each OS thread gets its own InferenceSession — zero mutex contention.
"""
import os
import hashlib
import threading
import numpy as np
import onnxruntime as ort

from .config import (
    ONNX_PROVIDERS,
    VERIFY_MODEL_HASHES,
    EXPECTED_HASH_V2,
    EXPECTED_HASH_SE,
    MODEL_V2,
    MODEL_SE,
    L1_LIVE_CLASS_INDEX,
)
from .utils import softmax

_thread_local = threading.local()


def _sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def _get_session(model_path: str) -> ort.InferenceSession:
    """
    Return a thread-local ONNX InferenceSession for the given model path.
    Sessions are created once per thread per model — completely thread-safe.
    """
    key = f"_ort_{model_path}"
    if not hasattr(_thread_local, key):
        if not os.path.isfile(model_path):
            raise FileNotFoundError(
                f"Anti-spoof model not found: {model_path}\n"
                "Run: python -m anti_spoof.download_models  to fetch them."
            )
        if VERIFY_MODEL_HASHES:
            expected = EXPECTED_HASH_V2 if model_path == MODEL_V2 else EXPECTED_HASH_SE
            actual = _sha256_of(model_path)
            if actual != expected.upper():
                raise RuntimeError(
                    f"Model hash mismatch for {os.path.basename(model_path)}.\n"
                    f"  Expected: {expected}\n  Got:      {actual}\n"
                    "The model file may be corrupted or tampered."
                )
        sess = ort.InferenceSession(model_path, providers=ONNX_PROVIDERS)
        setattr(_thread_local, key, sess)
    return getattr(_thread_local, key)


class AntiSpoofModel:
    """
    Thin wrapper around a single ONNX anti-spoof model.
    Thread-safe: each calling thread gets its own session.
    """

    def __init__(self, model_path: str):
        self.model_path = model_path

    def predict_score(self, preprocessed: np.ndarray) -> float:
        """
        Run inference and return the liveness probability [0, 1].

        Args:
            preprocessed: float32 NCHW array (1, 3, 80, 80)
        Returns:
            Probability that the face is REAL (live).
        """
        sess = _get_session(self.model_path)
        inp_name = sess.get_inputs()[0].name
        logits = sess.run(None, {inp_name: preprocessed})[0][0]
        probs = softmax(logits)
        idx = min(L1_LIVE_CLASS_INDEX, len(probs) - 1)
        return float(probs[idx])
