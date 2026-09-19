"""Per-user sliding window rate limiter for API endpoints.

Prevents abuse by limiting how many requests a user can make within
a time window. Each user-endpoint pair gets its own counter.
"""
import time
import threading
from collections import defaultdict

class SlidingWindowRateLimiter:
    """Sliding window rate limiter per (user, endpoint) pair.
    
    Thread-safe. Uses a deque of timestamps per key to track request times.
    """

    def __init__(self, max_requests: int = 5, window_seconds: int = 60):
        self.max_requests = max_requests
        self.window_seconds = window_seconds
        self._lock = threading.Lock()
        self._windows: dict[str, list[float]] = defaultdict(list)

    def _make_key(self, user_id: str, endpoint: str) -> str:
        return f"{user_id}:{endpoint}"

    def is_allowed(self, user_id: str, endpoint: str) -> tuple[bool, int]:
        """Check if the request is allowed.
        
        Returns (allowed: bool, retry_after_seconds: int).
        """
        key = self._make_key(user_id, endpoint)
        now = time.time()
        window_start = now - self.window_seconds

        with self._lock:
            timestamps = self._windows[key]
            # Remove expired entries
            while timestamps and timestamps[0] < window_start:
                timestamps.pop(0)

            if len(timestamps) >= self.max_requests:
                oldest = timestamps[0]
                retry_after = int(self.window_seconds - (now - oldest))
                return False, max(1, retry_after)

            timestamps.append(now)
            return True, 0

    def get_remaining(self, user_id: str, endpoint: str) -> int:
        """Get remaining requests in the current window."""
        key = self._make_key(user_id, endpoint)
        now = time.time()
        window_start = now - self.window_seconds

        with self._lock:
            timestamps = self._windows[key]
            while timestamps and timestamps[0] < window_start:
                timestamps.pop(0)
            return max(0, self.max_requests - len(timestamps))

    def reset(self, user_id: str, endpoint: str) -> None:
        """Reset rate limit for a user-endpoint pair."""
        key = self._make_key(user_id, endpoint)
        with self._lock:
            self._windows.pop(key, None)


attendance_rate_limiter = SlidingWindowRateLimiter(
    max_requests=10,
    window_seconds=60,
)

face_register_rate_limiter = SlidingWindowRateLimiter(
    max_requests=5,
    window_seconds=120,
)
