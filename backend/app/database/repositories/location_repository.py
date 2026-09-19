"""Location repository for user location tracking."""
import logging
from typing import Optional, Dict, Any, List
import asyncpg
from datetime import datetime
from decimal import Decimal
from ..connection import db_pool
from .base_repository import BaseRepository
from ..models import UserLocationLog, UserLatestLocation

logger = logging.getLogger(__name__)


class LocationRepository(BaseRepository):
    """Repository for user location tracking operations."""

    async def update_user_location(self, location_data: Dict[str, Any]) -> None:
        """Update user location (UPSERT into latest locations + INSERT into logs).
        
        Args:
            location_data: Dict containing:
                - reg_no: Registration number
                - latitude: Latitude as Decimal or float
                - longitude: Longitude as Decimal or float
                - timestamp: Timestamp of location
                - location_name: Optional location name
                - accuracy: Optional accuracy in meters
        """
        reg_no = location_data["reg_no"]
        latitude = location_data["latitude"]
        longitude = location_data["longitude"]
        timestamp = location_data["timestamp"]
        location_name = location_data.get("location_name")
        accuracy = location_data.get("accuracy")
        
        async with self.pool.acquire() as conn:
            async with conn.transaction():
                # Insert into location logs (always)
                await conn.execute(
                    """
                    INSERT INTO user_location_logs
                    (reg_no, timestamp, latitude, longitude, location_name, accuracy)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    """,
                    reg_no, timestamp, latitude, longitude, location_name, accuracy
                )
                
                # Upsert into latest locations
                await conn.execute(
                    """
                    INSERT INTO user_latest_locations
                    (reg_no, latitude, longitude, timestamp, location_name, accuracy)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (reg_no) DO UPDATE SET
                        latitude = EXCLUDED.latitude,
                        longitude = EXCLUDED.longitude,
                        timestamp = EXCLUDED.timestamp,
                        location_name = EXCLUDED.location_name,
                        accuracy = EXCLUDED.accuracy
                    """,
                    reg_no, latitude, longitude, timestamp, location_name, accuracy
                )
        
        logger.info(f"Updated location for {reg_no} at {timestamp}")
    
    async def get_latest_locations(self, reg_nos: List[str] | None = None) -> List[dict]:
        """Get latest known locations for users.
        
        Args:
            reg_nos: Optional list of registration numbers to filter by.
                     If None, returns all users' latest locations.
            
        Returns:
            List of location dicts
        """
        if reg_nos is not None and len(reg_nos) > 0:
            # Build dynamic IN clause
            placeholders = ",".join(f"${i+1}" for i in range(len(reg_nos)))
            query = f"""
                SELECT * FROM user_latest_locations
                WHERE reg_no IN ({placeholders})
                ORDER BY timestamp DESC
            """
            rows = await self.fetch(query, *reg_nos)
        else:
            rows = await self.fetch("SELECT * FROM user_latest_locations ORDER BY timestamp DESC")
        
        return [dict(row) for row in rows]
    
    async def get_location_history(self, reg_no: str, limit: int = 500) -> List[dict]:
        """Get location history for a user.
        
        Args:
            reg_no: Registration number
            limit: Maximum number of records to return
            
        Returns:
            List of location log dicts sorted by timestamp descending
        """
        rows = await self.fetch(
            """
            SELECT * FROM user_location_logs
            WHERE reg_no = $1
            ORDER BY timestamp DESC
            LIMIT $2
            """,
            reg_no, limit
        )
        return [dict(row) for row in rows]
    
    async def get_live_user_locations(self) -> List[dict]:
        """Get latest locations for all users.
        
        Returns:
            List of latest location dicts joined with user info
        """
        rows = await self.fetch(
            """
            SELECT
                ull.reg_no,
                ull.latitude,
                ull.longitude,
                ull.timestamp,
                ull.location_name,
                ull.accuracy,
                u.name,
                u.dept,
                u.role
            FROM user_latest_locations ull
            JOIN users u ON ull.reg_no = u.reg_no
            WHERE u.is_active = TRUE
            ORDER BY ull.timestamp DESC
            """
        )
        return [dict(row) for row in rows]
    
    async def get_user_location_at_time(self, reg_no: str, timestamp: datetime) -> Optional[dict]:
        """Get the closest location record for a user at or before a given time.
        
        Args:
            reg_no: Registration number
            timestamp: Target timestamp
            
        Returns:
            Location log dict or None
        """
        row = await self.fetchrow(
            """
            SELECT * FROM user_location_logs
            WHERE reg_no = $1 AND timestamp <= $2
            ORDER BY timestamp DESC
            LIMIT 1
            """,
            reg_no, timestamp
        )
        return dict(row) if row else None
    
    async def delete_old_location_logs(self, older_than_days: int = 90) -> int:
        """Delete location logs older than specified number of days.
        
        Args:
            older_than_days: Age threshold in days
            
        Returns:
            Number of rows deleted
        """
        result = await self.execute(
            """
            DELETE FROM user_location_logs
            WHERE timestamp < (NOW() - ($1 || ' days')::interval)
            """,
            str(older_than_days)
        )
        # result is a status string like "DELETE 42"
        deleted = int(result.split()[1]) if result else 0
        logger.info(f"Deleted {deleted} old location log records")
        return deleted