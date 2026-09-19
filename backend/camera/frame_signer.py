"""
frame_signer.py — HMAC-SHA256 frame signer for camera capture endpoints.
Used by client capture agents or local edge nodes to sign raw frames
before transmission to the VisionGate backend.
"""
import hmac
import hashlib
from typing import Union


class FrameSigner:
    """
    Signs raw frame JPEG bytes or bytebuffers using an assigned camera secret key.
    """

    def __init__(self, camera_id: str, secret_key: Union[str, bytes], algorithm: str = "sha256"):
        self.camera_id = camera_id
        self.secret_key = secret_key.encode("utf-8") if isinstance(secret_key, str) else secret_key
        self.algorithm = algorithm

    def sign_frame(self, frame_bytes: bytes, bytes_to_sign: int = 2048) -> str:
        """
        Compute HMAC signature for the first `bytes_to_sign` bytes of the frame.
        """
        payload = frame_bytes[:bytes_to_sign]
        return hmac.new(self.secret_key, payload, self.algorithm).hexdigest()
