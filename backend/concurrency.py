"""Per-user concurrency guard to prevent race conditions in face verification.

When a user opens multiple tabs/browser windows and triggers face verification
simultaneously, the camera may be accessed by multiple processes causing
exceptions. This module ensures only ONE verification request per user
runs at a time.
"""
import asyncio
import threading
from functools import wraps

_user_semaphores: dict[str, asyncio.Semaphore] = {}
_user_semaphores_lock = threading.Lock()


def get_user_semaphore(user_id: str, max_concurrent: int = 1) -> asyncio.Semaphore:
    """Get or create an asyncio.Semaphore for the given user.
    
    Each user gets their own semaphore limiting concurrent operations.
    Default max_concurrent=1 ensures only one verification per user at a time.
    """
    global _user_semaphores
    with _user_semaphores_lock:
        if user_id not in _user_semaphores:
            _user_semaphores[user_id] = asyncio.Semaphore(max_concurrent)
        return _user_semaphores[user_id]


def acquire_user_lock(user_id: str, max_concurrent: int = 1) -> asyncio.Semaphore:
    sem = get_user_semaphore(user_id, max_concurrent)
    return sem
