"""Database connection pool management using asyncpg."""
import asyncpg
import os
import logging
from typing import Optional

logger = logging.getLogger(__name__)


class DatabasePool:
    """Singleton class for managing asyncpg connection pool."""
    
    _instance: Optional['DatabasePool'] = None
    _pool: Optional[asyncpg.Pool] = None
    
    def __new__(cls) -> 'DatabasePool':
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance
    
    async def init_pool(self) -> None:
        """Initialize the connection pool with environment variables."""
        if self._pool is not None:
            logger.warning("Database pool already initialized")
            return
        
        try:
            dsn = (
                f"host={os.getenv('PG_HOST', 'localhost')}"
                f" port={os.getenv('PG_PORT', '5432')}"
                f" user={os.getenv('PG_USER', 'postgres')}"
                f" password={os.getenv('PG_PASSWORD', '')}"
                f" dbname={os.getenv('PG_DB', 'attenda')}"
            )
            
            self._pool = await asyncpg.create_pool(
                dsn,
                min_size=int(os.getenv('PG_POOL_MIN_SIZE', '5')),
                max_size=int(os.getenv('PG_POOL_MAX_SIZE', '20')),
                command_timeout=60,
                init=self._init_connection
            )
            logger.info("Database connection pool initialized")
        except Exception as e:
            logger.error(f"Failed to initialize database pool: {e}")
            raise
    
    async def _init_connection(self, connection: asyncpg.Connection) -> None:
        """Initialize each new connection with required extensions and settings."""
        try:
            # Enable pgvector extension
            await connection.execute("CREATE EXTENSION IF NOT EXISTS vector")
            # Set timezone to UTC
            await connection.execute("SET timezone TO UTC")
            logger.debug("Initialized database connection with pgvector and UTC timezone")
        except Exception as e:
            logger.error(f"Failed to initialize connection: {e}")
            raise
    
    def acquire(self):
        """Acquire a connection from the pool."""
        if self._pool is None:
            raise RuntimeError("Database pool not initialized. Call init_pool() first.")
        return self._pool.acquire()
    
    async def close(self) -> None:
        """Close the connection pool."""
        if self._pool is not None:
            await self._pool.close()
            self._pool = None
            logger.info("Database connection pool closed")
    
    @property
    def pool(self) -> Optional[asyncpg.Pool]:
        """Get the connection pool."""
        return self._pool


# Global instance
db_pool = DatabasePool()


async def get_db_connection():
    """Dependency to get a database connection."""
    async with db_pool.acquire() as connection:
        yield connection