# Caching Module
# Extracted from main.py for better organization

import os
import json
import time
import threading
from collections import OrderedDict
from typing import Optional, Dict, Any
from concurrent.futures import ThreadPoolExecutor

# Single background thread executor to serialize cache writes sequentially
_persist_executor = ThreadPoolExecutor(max_workers=1)

class LRUCache:
    """Thread-safe LRU cache with memory limits and optional persistence."""

    def __init__(self, max_size: int = 1000, ttl_seconds: int = None, persist_file: str = None):
        self.max_size = max_size
        self.ttl_seconds = ttl_seconds
        self.persist_file = persist_file
        self.cache = OrderedDict()
        self.access_times = {}
        self.lock = threading.Lock()
        self.hits = 0
        self.misses = 0
        self.evictions = 0

        # Load persisted data if file exists
        if persist_file and os.path.exists(persist_file):
            try:
                with open(persist_file, 'r') as f:
                    data = json.load(f)
                    for key, value in data.items():
                        if not self._is_expired(key):
                            self.cache[key] = value
                            self.access_times[key] = time.time()
                print(f"Loaded {len(self.cache)} items from {persist_file}")
            except Exception as e:
                print(f"Failed to load cache from {persist_file}: {e}")
                # Rename the corrupted file so we start fresh and don't fail next time
                try:
                    corrupted_file = persist_file + ".corrupted"
                    if os.path.exists(corrupted_file):
                        try:
                            os.remove(corrupted_file)
                        except:
                            pass
                    os.rename(persist_file, corrupted_file)
                    print(f"Renamed corrupted cache file to {corrupted_file} and starting fresh.")
                except Exception as backup_err:
                    print(f"Failed to handle corrupted cache file: {backup_err}")

    def _is_expired(self, key: str) -> bool:
        """Check if cache entry is expired."""
        if self.ttl_seconds is None:
            return False
        access_time = self.access_times.get(key, 0)
        return (time.time() - access_time) > self.ttl_seconds

    def get(self, key: str):
        """Get item from cache."""
        with self.lock:
            if key in self.cache:
                if self._is_expired(key):
                    del self.cache[key]
                    del self.access_times[key]
                    self.misses += 1
                    return None
                # Move to end (most recently used)
                self.cache.move_to_end(key)
                self.access_times[key] = time.time()
                self.hits += 1
                return self.cache[key]
            self.misses += 1
            return None

    def put(self, key: str, value):
        """Put item in cache."""
        with self.lock:
            if key in self.cache:
                self.cache.move_to_end(key)
            else:
                if len(self.cache) >= self.max_size:
                    # Remove least recently used
                    oldest_key, _ = self.cache.popitem(last=False)
                    if oldest_key in self.access_times:
                        del self.access_times[oldest_key]
                    self.evictions += 1

            self.cache[key] = value
            self.access_times[key] = time.time()

            # Persist if configured (asynchronously to avoid I/O bottlenecks)
            if self.persist_file:
                # Take a snapshot of current cache items under the lock to prevent thread-safety issues during serialization
                data_copy = {}
                for k, v in self.cache.items():
                    if not self._is_expired(k):
                        data_copy[k] = v.tolist() if hasattr(v, 'tolist') else v
                _persist_executor.submit(self._persist_bg, self.persist_file, data_copy)

    def remove(self, key: str):
        """Remove item from cache."""
        with self.lock:
            if key in self.cache:
                del self.cache[key]
                if key in self.access_times:
                    del self.access_times[key]

    def clear(self):
        """Clear all cache entries."""
        with self.lock:
            self.cache.clear()
            self.access_times.clear()

    def size(self) -> int:
        """Get current cache size."""
        with self.lock:
            return len(self.cache)

    def stats(self) -> dict:
        """Get cache statistics."""
        with self.lock:
            total_requests = self.hits + self.misses
            hit_rate = (self.hits / total_requests * 100) if total_requests > 0 else 0
            return {
                "size": len(self.cache),
                "max_size": self.max_size,
                "hits": self.hits,
                "misses": self.misses,
                "evictions": self.evictions,
                "hit_rate_percent": round(hit_rate, 2)
            }

    @staticmethod
    def _persist_bg(filepath: str, data: dict):
        """Write cache snapshot to disk in a background thread."""
        try:
            with open(filepath, 'w') as f:
                json.dump(data, f, default=str)
        except Exception as e:
            print(f"Failed to persist cache to {filepath}: {e}")

class CacheDictAdapter:
    """Adapter to provide dict-like access to LRUCache for backward compatibility."""
    def __init__(self, cache: LRUCache):
        self.cache = cache

    def __getitem__(self, key):
        value = self.cache.get(key)
        if value is None:
            raise KeyError(key)
        return value

    def __setitem__(self, key, value):
        self.cache.put(key, value)

    def __delitem__(self, key):
        self.cache.remove(key)

    def __contains__(self, key):
        return self.cache.get(key) is not None

    def get(self, key, default=None):
        return self.cache.get(key) or default

    def pop(self, key, default=None):
        value = self.cache.get(key)
        if value is not None:
            self.cache.remove(key)
            return value
        return default

# Initialize enhanced caches
_face_profile_cache = LRUCache(
    max_size=500,
    ttl_seconds=3600 * 24,  # 24 hours
    persist_file=os.path.join(os.path.dirname(__file__), "face_cache.json")
)

# Lockout and failed attempts with size limits
_lockout_storage = LRUCache(max_size=1000, ttl_seconds=3600)  # Auto-expire after 1 hour
_failed_attempts = LRUCache(max_size=1000, ttl_seconds=3600 * 24)  # 24 hours

# Query result caching for frequently accessed data
_query_cache = LRUCache(
    max_size=1000,
    ttl_seconds=1800,  # 30 minutes for query results
)

# Legacy compatibility
_face_profile_dict = CacheDictAdapter(_face_profile_cache)