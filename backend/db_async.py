"""Async wrapper for pg_adapter - offloads all sync DB calls to a thread pool.

This prevents the synchronous pg_adapter.cursor operations from blocking
the asyncio event loop when used inside FastAPI async endpoints.
"""
import asyncio
import functools
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Optional

import pg_adapter

_db_executor = ThreadPoolExecutor(max_workers=30, thread_name_prefix="db_worker")

_cursor = pg_adapter.cursor


async def async_execute(sql: str, params: Optional[tuple] = None) -> None:
    """Execute a statement (INSERT/UPDATE/DELETE) without blocking the event loop."""
    loop = asyncio.get_running_loop()
    if params is not None:
        await loop.run_in_executor(_db_executor, _cursor.execute, sql, params)
    else:
        await loop.run_in_executor(_db_executor, _cursor.execute, sql)


async def async_fetchone(sql: str, params: Optional[tuple] = None) -> Optional[tuple]:
    """Fetch a single row without blocking the event loop."""
    loop = asyncio.get_running_loop()
    if params is not None:
        return await loop.run_in_executor(_db_executor, _cursor.execute, sql, params).then(
            lambda _: None
        )
    # We need a different approach since run_in_executor wraps execute()
    # and fetchone() is a separate call
    fn = functools.partial(_do_fetchone, sql, params)
    return await loop.run_in_executor(_db_executor, fn)


def _do_fetchone(sql: str, params: Optional[tuple] = None) -> Optional[tuple]:
    if params is not None:
        _cursor.execute(sql, params)
    else:
        _cursor.execute(sql)
    return _cursor.fetchone()


async def async_fetchall(sql: str, params: Optional[tuple] = None) -> list[tuple]:
    """Fetch all rows without blocking the event loop."""
    fn = functools.partial(_do_fetchall, sql, params)
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_db_executor, fn)


def _do_fetchall(sql: str, params: Optional[tuple] = None) -> list[tuple]:
    if params is not None:
        _cursor.execute(sql, params)
    else:
        _cursor.execute(sql)
    return _cursor.fetchall()


async def async_fetchval(sql: str, params: Optional[tuple] = None, column: int = 0) -> Any:
    """Fetch a single value without blocking the event loop."""
    fn = functools.partial(_do_fetchval, sql, params, column)
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(_db_executor, fn)


def _do_fetchval(sql: str, params: Optional[tuple] = None, column: int = 0) -> Any:
    if params is not None:
        _cursor.execute(sql, params)
    else:
        _cursor.execute(sql)
    row = _cursor.fetchone()
    if row is None:
        return None
    return row[column] if column < len(row) else None


async def async_commit() -> None:
    """Commit the current transaction (no-op with autocommit, here for compatibility)."""
    # pg_adapter uses autocommit=True, so this is a no-op
    # but we still offload to avoid any potential blocking
    loop = asyncio.get_running_loop()
    await loop.run_in_executor(_db_executor, _cursor.commit)


def run_sync_in_thread(fn, *args, **kwargs):
    """Run an arbitrary synchronous function in the thread pool.
    
    Use this for CPU-bound or blocking operations that aren't DB calls.
    Returns a coroutine that must be awaited.
    """
    loop = asyncio.get_running_loop()
    return loop.run_in_executor(_db_executor, functools.partial(fn, *args, **kwargs))
