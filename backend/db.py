"""
Async PostgreSQL database layer for VisionGate.
Replaces all sqlite3 direct calls with asyncpg pool.
"""

import os
import asyncpg
from contextlib import asynccontextmanager

# PostgreSQL connection pool (initialized at startup)
_pool = None

PG_CONFIG = {
    "host": os.environ.get("PG_HOST", "localhost"),
    "port": int(os.environ.get("PG_PORT", "5432")),
    "user": os.environ.get("PG_USER", "attenda"),
    "password": os.environ.get("PG_PASSWORD", "attenda_password"),
    "database": os.environ.get("PG_DB", "attenda"),
}


async def init_pool(min_size=5, max_size=20):
    """Initialize the connection pool. Call once at startup."""
    global _pool
    _pool = await asyncpg.create_pool(
        host=PG_CONFIG["host"],
        port=PG_CONFIG["port"],
        user=PG_CONFIG["user"],
        password=PG_CONFIG["password"],
        database=PG_CONFIG["database"],
        min_size=min_size,
        max_size=max_size,
        command_timeout=30,
    )
    print(
        f"PostgreSQL pool initialized: {PG_CONFIG['host']}:{PG_CONFIG['port']}/{PG_CONFIG['database']}"
    )


async def close_pool():
    """Close the connection pool. Call at shutdown."""
    global _pool
    if _pool:
        await _pool.close()
        _pool = None
        print("PostgreSQL pool closed")


def get_pool():
    """Get the current pool. Raises if not initialized."""
    if _pool is None:
        raise RuntimeError("Database pool not initialized. Call init_pool() first.")
    return _pool


@asynccontextmanager
async def acquire():
    """Acquire a connection from the pool. Use as async context manager."""
    pool = get_pool()
    async with pool.acquire() as conn:
        yield conn


async def fetchrow(query, *args):
    """Fetch a single row. Returns asyncpg.Record or None."""
    async with acquire() as conn:
        return await conn.fetchrow(query, *args)


async def fetch(query, *args):
    """Fetch multiple rows. Returns list of asyncpg.Record."""
    async with acquire() as conn:
        return await conn.fetch(query, *args)


async def fetchval(query, *args, column=0):
    """Fetch a single value. Returns the value or None."""
    async with acquire() as conn:
        return await conn.fetchval(query, *args, column=column)


async def execute(query, *args):
    """Execute a statement (INSERT/UPDATE/DELETE). Returns status string."""
    async with acquire() as conn:
        return await conn.execute(query, *args)


async def executemany(query, args_list):
    """Execute a statement with multiple argument sets."""
    async with acquire() as conn:
        return await conn.executemany(query, args_list)


async def insert_returning_id(query, *args):
    """Execute an INSERT and return the new id. Uses RETURNING id."""
    async with acquire() as conn:
        row = await conn.fetchrow(query, *args)
        return row["id"] if row else None


async def transaction():
    """Return a transaction context manager.
    Usage:
        async with transaction() as conn:
            await conn.execute(...)
    """
    pool = get_pool()
    return _TransactionContext(pool)


class _TransactionContext:
    def __init__(self, pool):
        self._pool = pool
        self._conn = None
        self._tx = None

    async def __aenter__(self):
        self._conn = await self._pool.acquire()
        self._tx = self._conn.transaction()
        await self._tx.start()
        return self._conn

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        try:
            if exc_type is None:
                await self._tx.commit()
            else:
                await self._tx.rollback()
        finally:
            await self._pool.release(self._conn)
        return False
