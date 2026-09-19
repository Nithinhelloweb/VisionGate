"""
ingestion.py — Unified VideoCapture (USB) and RTSP camera ingestion worker.
Reads frames at target FPS, signs them for Layer 5 trust validation, and pushes
to a BoundedFrameQueue with backpressure.
"""
import time
import threading
import cv2
import numpy as np
from typing import Optional, Union
from .frame_queue import BoundedFrameQueue
from .frame_signer import FrameSigner


class CameraIngester:
    """
    Continuous camera frame ingestion daemon.
    Supports camera device indexes (0, 1) or stream URLs (rtsp://, http://).
    """

    def __init__(
        self,
        camera_id: str,
        source: Union[int, str] = 0,
        target_fps: int = 15,
        secret_key: Optional[str] = None,
        max_queue_depth: int = 4,
    ):
        self.camera_id = camera_id
        self.source = source
        self.target_fps = target_fps
        self.frame_interval = 1.0 / max(1, target_fps)
        self.queue = BoundedFrameQueue(max_depth=max_queue_depth)
        self.signer = FrameSigner(camera_id, secret_key) if secret_key else None

        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._cap: Optional[cv2.VideoCapture] = None
        self._fps_actual: float = 0.0
        self._frames_read: int = 0

    def start(self) -> None:
        """Start the ingestion background worker thread."""
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._worker_loop, daemon=True, name=f"CameraIngester-{self.camera_id}")
        self._thread.start()

    def stop(self) -> None:
        """Stop frame ingestion and release device."""
        self._running = False
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        if self._cap and self._cap.isOpened():
            self._cap.release()
            self._cap = None

    def _worker_loop(self) -> None:
        self._cap = cv2.VideoCapture(self.source)
        if not self._cap.isOpened():
            print(f"[CameraIngester] ERROR: Failed to open camera source: {self.source}")
            self._running = False
            return

        last_frame_time = time.time()
        fps_timer = time.time()
        fps_frames = 0

        while self._running:
            now = time.time()
            elapsed = now - last_frame_time

            if elapsed < self.frame_interval:
                time.sleep(max(0.001, self.frame_interval - elapsed))
                continue

            ret, frame = self._cap.read()
            if not ret or frame is None:
                time.sleep(0.05)
                continue

            last_frame_time = time.time()
            self._frames_read += 1
            fps_frames += 1

            # Update FPS calculation every second
            if now - fps_timer >= 1.0:
                self._fps_actual = fps_frames / (now - fps_timer)
                fps_timer = now
                fps_frames = 0

            # Encode and sign if camera secret key configured
            signature = None
            if self.signer:
                ret_enc, enc_jpg = cv2.imencode(".jpg", frame, [int(cv2.IMWRITE_JPEG_QUALITY), 80])
                if ret_enc:
                    signature = self.signer.sign_frame(enc_jpg.tobytes())

            payload = {
                "camera_id": self.camera_id,
                "frame": frame,
                "timestamp": now,
                "signature": signature,
                "frame_id": self._frames_read,
            }
            self.queue.put_nowait(payload)

        if self._cap:
            self._cap.release()
            self._cap = None

    @property
    def is_alive(self) -> bool:
        return self._running and self._thread is not None and self._thread.is_alive()

    @property
    def fps(self) -> float:
        return self._fps_actual

    @property
    def stats(self) -> dict:
        return {
            "camera_id": self.camera_id,
            "source": str(self.source),
            "is_alive": self.is_alive,
            "fps_target": self.target_fps,
            "fps_actual": round(self._fps_actual, 1),
            "frames_read": self._frames_read,
            "queue_stats": self.queue.stats,
        }
