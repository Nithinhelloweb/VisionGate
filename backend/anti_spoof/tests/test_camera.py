"""
tests/test_camera.py — Unit tests for camera ingestion and tracking components.
"""
import sys, os
import numpy as np
import pytest

_BACKEND = os.path.join(os.path.dirname(__file__), "..", "..")
sys.path.insert(0, _BACKEND)

from camera.frame_queue import BoundedFrameQueue
from camera.frame_signer import FrameSigner
from camera.tracker import SimpleFaceTracker


def test_frame_queue_bounded_drop():
    q = BoundedFrameQueue(max_depth=3)
    for i in range(10):
        q.put_nowait(f"frame_{i}")
    assert q.qsize() == 3
    assert q.stats["dropped_count"] == 7
    # Oldest retained frame should be frame_7
    assert q.get_nowait() == "frame_7"


def test_frame_signer():
    signer = FrameSigner(camera_id="cam_main", secret_key="secret123")
    fake_frame = b"fake_jpeg_header_bytes_1234567890" * 100
    sig1 = signer.sign_frame(fake_frame)
    sig2 = signer.sign_frame(fake_frame)
    assert sig1 == sig2
    assert len(sig1) == 64  # sha256 hex length


def test_face_tracker_association():
    tracker = SimpleFaceTracker(iou_threshold=0.3)
    
    # Frame 1: two faces
    f1_boxes = [[100, 100, 200, 200], [300, 100, 400, 200]]
    tracks_f1 = tracker.update(f1_boxes)
    assert len(tracks_f1) == 2
    tid1, tid2 = tracks_f1[0][0], tracks_f1[1][0]
    assert tid1 != tid2

    # Frame 2: slightly moved faces
    f2_boxes = [[105, 102, 203, 198], [302, 98, 405, 202]]
    tracks_f2 = tracker.update(f2_boxes)
    assert len(tracks_f2) == 2
    res_tids = [t[0] for t in tracks_f2]
    assert tid1 in res_tids
    assert tid2 in res_tids


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
