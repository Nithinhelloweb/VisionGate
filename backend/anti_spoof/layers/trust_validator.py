"""
Layer 5 — Camera Trust Validator (HMAC-SHA256 frame authentication).

Prevents virtual camera injection attacks (OBS, ManyCam, software fakes).
Only registered hardware that knows the per-camera HMAC secret can pass.
"""
import hmac
import hashlib
from typing import Optional
from ..config import L5_HMAC_ALGORITHM, L5_BYTES_TO_SIGN


class TrustValidator:
    """
    Validates HMAC signatures on incoming frames.
    Camera secrets are stored in trusted_cameras DB table (encrypted at rest).
    """

    def __init__(self):
        # In-memory cache: camera_id -> secret_bytes
        self._keys: dict = {}

    def register_camera(self, camera_id: str, secret_key: str) -> None:
        """Register a camera's HMAC secret (called at startup from DB)."""
        self._keys[camera_id] = secret_key.encode() if isinstance(secret_key, str) else secret_key

    def sign(self, frame_jpeg_bytes: bytes, camera_id: str) -> Optional[str]:
        """
        Generate HMAC signature for the first L5_BYTES_TO_SIGN bytes of a frame.
        Used by the capture side (dev/testing only — production cameras sign in firmware).
        """
        key = self._keys.get(camera_id)
        if key is None:
            return None
        payload = frame_jpeg_bytes[:L5_BYTES_TO_SIGN]
        return hmac.new(key, payload, L5_HMAC_ALGORITHM).hexdigest()

    def validate(self, frame_jpeg_bytes: bytes, camera_id: str, signature: str) -> bool:
        """
        Validate an incoming frame's HMAC signature.
        Returns False (reject) if camera is unknown or signature doesn't match.
        Timing-safe via hmac.compare_digest.
        """
        key = self._keys.get(camera_id)
        if key is None:
            # Unknown camera — reject
            return False
        payload = frame_jpeg_bytes[:L5_BYTES_TO_SIGN]
        expected = hmac.new(key, payload, L5_HMAC_ALGORITHM).hexdigest()
        return hmac.compare_digest(expected, signature)

    def is_camera_trusted(self, camera_id: str) -> bool:
        """Check if a camera has a registered key (without frame validation)."""
        return camera_id in self._keys

    def unregister_camera(self, camera_id: str) -> None:
        self._keys.pop(camera_id, None)
