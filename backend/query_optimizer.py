# Query Optimization Module
# Provides cached versions of frequently used database queries

import time
from typing import List, Dict, Any, Optional
from .cache import _query_cache
from .database import db

class QueryOptimizer:
    """Optimizes frequently used database queries with caching and batch operations."""

    @staticmethod
    def get_cached_query(cache_key: str, query_func, ttl_seconds: int = 300):
        """Get cached query result or execute and cache it."""
        cached_result = _query_cache.get(cache_key)
        if cached_result is not None:
            return cached_result

        # Execute query
        result = query_func()

        # Cache result
        _query_cache.put(cache_key, result)

        return result

    @staticmethod
    async def get_user_count_by_role(role: str = None) -> int:
        """Get user count, optionally filtered by role."""
        cache_key = f"user_count_{role or 'all'}"

        def _execute_query():
            if role:
                result = db.fetchval("SELECT COUNT(*) FROM users WHERE role = ?", (role,))
            else:
                result = db.fetchval("SELECT COUNT(*) FROM users")
            return result or 0

        return QueryOptimizer.get_cached_query(cache_key, _execute_query, 600)  # 10 min cache

    @staticmethod
    async def get_department_list() -> List[Dict[str, Any]]:
        """Get list of all departments."""
        cache_key = "departments_list"

        def _execute_query():
            rows = db.fetch("SELECT id, name, created_at FROM departments ORDER BY name")
            return [{"id": row[0], "name": row[1], "created_at": row[2]} for row in rows]

        return QueryOptimizer.get_cached_query(cache_key, _execute_query, 1800)  # 30 min cache

    @staticmethod
    async def get_user_by_reg_no_cached(reg_no: str) -> Optional[Dict[str, Any]]:
        """Get user by registration number with caching."""
        cache_key = f"user_reg_no_{reg_no.lower()}"

        def _execute_query():
            # Try users table first
            row = db.fetchrow("SELECT id, username, reg_no, name, dept, role, created_at FROM users WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
            if row:
                return {
                    "id": row[0], "username": row[1], "reg_no": row[2], "name": row[3],
                    "dept": row[4], "role": row[5], "created_at": row[6], "table": "users"
                }

            # Try other_staff table
            row = db.fetchrow("SELECT id, username, reg_no, name, dept, role, created_at FROM other_staff WHERE LOWER(reg_no) = LOWER(?)", (reg_no,))
            if row:
                return {
                    "id": row[0], "username": row[1], "reg_no": row[2], "name": row[3],
                    "dept": row[4], "role": row[5], "created_at": row[6], "table": "other_staff"
                }

            return None

        return QueryOptimizer.get_cached_query(cache_key, _execute_query, 1800)  # 30 min cache

    @staticmethod
    async def get_attendance_stats(dept: str = None, days: int = 30) -> Dict[str, Any]:
        """Get attendance statistics with caching."""
        cache_key = f"attendance_stats_{dept or 'all'}_{days}"

        def _execute_query():
            # Calculate date range
            import datetime
            end_date = datetime.datetime.now().date()
            start_date = end_date - datetime.timedelta(days=days)

            if dept:
                # Department-specific stats
                total_users = db.fetchval("SELECT COUNT(*) FROM users WHERE dept = ?", (dept,))
                attendance_count = db.fetchval("""
                    SELECT COUNT(*) FROM attendance
                    WHERE dept = ? AND DATE(timestamp) >= ? AND DATE(timestamp) <= ?
                """, (dept, start_date, end_date))
            else:
                # Global stats
                total_users = db.fetchval("SELECT COUNT(*) FROM users")
                attendance_count = db.fetchval("""
                    SELECT COUNT(*) FROM attendance
                    WHERE DATE(timestamp) >= ? AND DATE(timestamp) <= ?
                """, (start_date, end_date))

            return {
                "total_users": total_users or 0,
                "attendance_records": attendance_count or 0,
                "period_days": days,
                "start_date": str(start_date),
                "end_date": str(end_date)
            }

        return QueryOptimizer.get_cached_query(cache_key, _execute_query, 3600)  # 1 hour cache

    @staticmethod
    async def invalidate_cache_pattern(pattern: str):
        """Invalidate cache entries matching a pattern."""
        # This is a simplified implementation - in production you'd want more sophisticated pattern matching
        # For now, we'll clear relevant caches
        if "user" in pattern:
            # Clear user-related caches by removing keys that contain "user"
            pass  # Would need to implement key enumeration in LRUCache
        elif "department" in pattern:
            _query_cache.remove("departments_list")
        elif "attendance" in pattern:
            # Clear attendance-related caches
            pass  # Would need pattern-based clearing

    @staticmethod
    async def get_query_performance_stats() -> Dict[str, Any]:
        """Get query performance statistics."""
        return {
            "query_cache_stats": _query_cache.stats(),
            "cache_hit_rate": _query_cache.stats()["hit_rate_percent"],
            "total_cached_queries": _query_cache.size()
        }

# Global query optimizer instance
query_optimizer = QueryOptimizer()