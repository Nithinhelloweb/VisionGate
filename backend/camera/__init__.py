"""
Camera ingestion and multi-user tracking package for VisionGate.
Supports USB VideoCapture, RTSP streams, bounded frame queues, and cross-frame tracking.
"""
from .frame_queue import BoundedFrameQueue
from .frame_signer import FrameSigner
from .tracker import SimpleFaceTracker
from .ingestion import CameraIngester

__all__ = ["BoundedFrameQueue", "FrameSigner", "SimpleFaceTracker", "CameraIngester"]
