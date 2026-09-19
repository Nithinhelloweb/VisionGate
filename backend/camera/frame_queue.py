"""
frame_queue.py — Bounded async frame queue with drop-on-overflow backpressure.
Prevents frame backlog and latency drift when ingestion is faster than inference.
"""
import asyncio
from typing import Optional, Any


class BoundedFrameQueue:
    """
    Async queue that keeps at most `max_depth` frames.
    When a new frame arrives and the queue is full, the oldest frame is discarded.
    """

    def __init__(self, max_depth: int = 4):
        self.max_depth = max(1, max_depth)
        self._queue: asyncio.Queue = asyncio.Queue(maxsize=self.max_depth)
        self._dropped_count: int = 0
        self._total_pushed: int = 0

    async def put(self, item: Any) -> None:
        """Push an item. Discards the oldest element if full."""
        self._total_pushed += 1
        if self._queue.full():
            try:
                self._queue.get_nowait()
                self._dropped_count += 1
            except asyncio.QueueEmpty:
                pass
        await self._queue.put(item)

    def put_nowait(self, item: Any) -> None:
        """Synchronous/non-blocking put. Discards oldest element if full."""
        self._total_pushed += 1
        if self._queue.full():
            try:
                self._queue.get_nowait()
                self._dropped_count += 1
            except asyncio.QueueEmpty:
                pass
        try:
            self._queue.put_nowait(item)
        except asyncio.QueueFull:
            pass

    async def get(self) -> Any:
        """Wait and retrieve the next frame."""
        return await self._queue.get()

    def get_nowait(self) -> Optional[Any]:
        """Retrieve the next frame without blocking, or None if empty."""
        try:
            return self._queue.get_nowait()
        except asyncio.QueueEmpty:
            return None

    def qsize(self) -> int:
        return self._queue.qsize()

    def empty(self) -> bool:
        return self._queue.empty()

    @property
    def stats(self) -> dict:
        return {
            "current_size": self.qsize(),
            "max_depth": self.max_depth,
            "total_pushed": self._total_pushed,
            "dropped_count": self._dropped_count,
        }
