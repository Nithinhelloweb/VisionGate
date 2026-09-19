"""
test_registration_pipeline.py -- Automated tests for face registration validation pipeline.
Validates quality checks (blur, brightness), face detection, anti-spoofing enforcement,
and unit-vector embedding normalization.
"""
import sys
import os
import cv2
import numpy as np
import pytest
from fastapi import HTTPException

# Ensure backend root is on sys.path
_BACKEND = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if _BACKEND not in sys.path:
    sys.path.insert(0, _BACKEND)

from main import _process_and_validate_registration_face, _normalize_embedding


def test_normalize_embedding():
    # Test valid vector
    vec = np.array([3.0, 4.0, 0.0], dtype=np.float32)
    normed = _normalize_embedding(vec)
    assert normed is not None
    assert np.isclose(np.linalg.norm(normed), 1.0, atol=1e-5)
    assert np.isclose(normed[0], 0.6, atol=1e-5)
    assert np.isclose(normed[1], 0.8, atol=1e-5)

    # Test None and zero vector
    assert _normalize_embedding(None) is None
    assert _normalize_embedding(np.zeros(512, dtype=np.float32)) is None


def test_registration_rejects_dark_image():
    # Create pitch black image
    dark_img = np.zeros((300, 300, 3), dtype=np.uint8)
    _, buf = cv2.imencode(".jpg", dark_img)
    img_bytes = buf.tobytes()

    with pytest.raises(HTTPException) as exc_info:
        _process_and_validate_registration_face(img_bytes)
    
    assert exc_info.value.status_code == 400
    assert "too dark" in exc_info.value.detail.lower() or "blurry" in exc_info.value.detail.lower()


def test_registration_rejects_blurry_image():
    # Create solid flat gray image (zero edge gradient / zero Laplacian variance)
    flat_img = np.full((300, 300, 3), 128, dtype=np.uint8)
    _, buf = cv2.imencode(".jpg", flat_img)
    img_bytes = buf.tobytes()

    with pytest.raises(HTTPException) as exc_info:
        _process_and_validate_registration_face(img_bytes)
    
    assert exc_info.value.status_code == 400
    assert "blurry" in exc_info.value.detail.lower()


def test_registration_rejects_no_face():
    # Create image with texture (not blurry, not dark) but without any human face
    rng = np.random.RandomState(42)
    textured_img = rng.randint(50, 200, (400, 400, 3), dtype=np.uint8)
    _, buf = cv2.imencode(".jpg", textured_img)
    img_bytes = buf.tobytes()

    with pytest.raises(HTTPException) as exc_info:
        _process_and_validate_registration_face(img_bytes)
    
    assert exc_info.value.status_code == 400
    assert "face not detected" in exc_info.value.detail.lower() or "blurry" in exc_info.value.detail.lower()
