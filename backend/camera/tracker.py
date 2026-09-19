"""
tracker.py — Lightweight IoU and Centroid multi-face tracker.
Assigns persistent track_id to detected faces across frames.
Required by Layer 3 (Blink EAR) and Layer 4 (Optical Flow) temporal windows.
"""
import time
import numpy as np
from typing import List, Dict, Any, Tuple


def _compute_iou(bb1: List[float], bb2: List[float]) -> float:
    """Compute Intersection over Union between two [x1, y1, x2, y2] boxes."""
    xx1 = max(bb1[0], bb2[0])
    yy1 = max(bb1[1], bb2[1])
    xx2 = min(bb1[2], bb2[2])
    yy2 = min(bb1[3], bb2[3])

    w = max(0.0, xx2 - xx1)
    h = max(0.0, yy2 - yy1)
    intersection = w * h

    area1 = max(0.0, (bb1[2] - bb1[0]) * (bb1[3] - bb1[1]))
    area2 = max(0.0, (bb2[2] - bb2[0]) * (bb2[3] - bb2[1]))
    union = area1 + area2 - intersection
    if union <= 0.0:
        return 0.0
    return float(intersection / union)


class TrackedFace:
    def __init__(self, track_id: str, bbox: List[float]):
        self.track_id = track_id
        self.bbox = [float(x) for x in bbox[:4]]
        self.last_seen = time.time()
        self.hits = 1
        self.age = 1


class SimpleFaceTracker:
    """
    Online multi-target face tracker.
    Matches current detections to existing tracks via IoU score.
    Cleans up tracks that have not been seen for `max_lost_seconds`.
    """

    def __init__(self, iou_threshold: float = 0.30, max_lost_seconds: float = 2.0):
        self.iou_threshold = iou_threshold
        self.max_lost_seconds = max_lost_seconds
        self._next_id: int = 1
        self.tracks: Dict[str, TrackedFace] = {}

    def update(self, detected_bboxes: List[List[float]]) -> List[Tuple[str, List[float]]]:
        """
        Update tracker with new frame detections.
        
        Args:
            detected_bboxes: List of [x1, y1, x2, y2] bounding boxes.
            
        Returns:
            List of tuples: (track_id, bbox)
        """
        now = time.time()
        results: List[Tuple[str, List[float]]] = []

        # Remove stale tracks
        expired = [tid for tid, trk in self.tracks.items() if (now - trk.last_seen) > self.max_lost_seconds]
        for tid in expired:
            del self.tracks[tid]

        if not detected_bboxes:
            return results

        matched_tracks = set()
        matched_detections = set()

        # Match existing tracks with detections by IoU
        for det_idx, det_bbox in enumerate(detected_bboxes):
            best_iou = 0.0
            best_tid = None
            for tid, trk in self.tracks.items():
                if tid in matched_tracks:
                    continue
                iou = _compute_iou(det_bbox, trk.bbox)
                if iou > best_iou:
                    best_iou = iou
                    best_tid = tid

            if best_iou >= self.iou_threshold and best_tid is not None:
                matched_tracks.add(best_tid)
                matched_detections.add(det_idx)
                trk = self.tracks[best_tid]
                trk.bbox = [float(x) for x in det_bbox[:4]]
                trk.last_seen = now
                trk.hits += 1
                trk.age += 1
                results.append((best_tid, trk.bbox))

        # Create new tracks for unmatched detections
        for det_idx, det_bbox in enumerate(detected_bboxes):
            if det_idx not in matched_detections:
                tid = f"track_{self._next_id}"
                self._next_id += 1
                new_trk = TrackedFace(tid, det_bbox)
                self.tracks[tid] = new_trk
                results.append((tid, new_trk.bbox))

        return results

    def reset(self) -> None:
        """Reset all active tracks."""
        self.tracks.clear()
        self._next_id = 1
