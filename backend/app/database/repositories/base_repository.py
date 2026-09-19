"""Base repository for common async database operations."""
import logging
from typing import Optional, Any, List
import asyncpg
from ..connection import db_pool

logger = logging.getLogger(__name__)


class BaseRepository:
    """Base repository providing common async database operations."""

    def __init__(self, pool: asyncpg.Pool = None):
        self.pool = pool or db_pool.pool
    
    async def execute(self, query: str, *args, timeout: float = 30.0) -> Optional[str]:
        """Execute a query and return the status tag.
        
        Args:
            query: SQL query string with $1, $2, ... placeholders
            *args: Query parameters
            timeout: Query timeout in seconds
            
        Returns:
            Status tag string or None on error
        """
        async with self.pool.acquire() as conn:
            return await conn.execute(query, *args, timeout=timeout)
    
    async def fetchrow(self, query: str, *args, timeout: float = 30.0) -> Optional[asyncpg.Record]:
        """Execute a query and return the first row as a Record.
        
        Args:
            query: SQL query string
            *args: Query parameters
            timeout: Query timeout in seconds
            
        Returns:
            asyncpg.Record or None if no results
        """
        async with self.pool.acquire() as conn:
            return await conn.fetchrow(query, *args, timeout=timeout)
    
    async def fetch(self, query: str, *args, timeout: float = 30.0) -> List[asyncpg.Record]:
        """Execute a query and return all rows as a list of Records.
        
        Args:
            query: SQL query string
            *args: Query parameters
            timeout: Query timeout in seconds
            
        Returns:
            List of asyncpg.Record objects
        """
        async with self.pool.acquire() as conn:
            return await conn.fetch(query, *args, timeout=timeout)
    
    async def fetchval(self, query: str, *args, column: int = 0, timeout: float = 30.0) -> Any:
        """Execute a query and return a single value from the first row.
        
        Args:
            query: SQL query string
            *args: Query parameters
            column: Column index or name to fetch
            timeout: Query timeout in seconds
            
        Returns:
            Single value or None
        """
        async with self.pool.acquire() as conn:
            return await conn.fetchval(query, *args, column=column, timeout=timeout)
