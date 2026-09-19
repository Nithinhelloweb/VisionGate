"""Geo repository for database operations."""
import logging
from typing import List, Optional, Dict, Any
import asyncpg
from datetime import date
from decimal import Decimal
from ..connection import db_pool

logger = logging.getLogger(__name__)


class GeoRepository:
    """Repository for geo-fence and location-related database operations."""
    
    async def get_geo_fence_polygons(self) -> tuple:
        """Get geo-fence polygons from v2 table.
        
        Returns:
            Tuple of (outer_polygons, inner_polygons, limit_range_polygons) where each is a list of
            lists of (lat, lng) tuples.
        """
        async with db_pool.pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT polygon_type, polygon_group, latitude, longitude, point_order
                FROM geo_fence_coordinates_v2
                ORDER BY polygon_type, polygon_group, point_order
                """
            )
        
        grouped = {"outer": {}, "inner": {}, "limit_range": {}}
        for row in rows:
            ptype = row["polygon_type"]
            pgroup = int(row["polygon_group"])
            lat = float(row["latitude"])
            lng = float(row["longitude"])
            grouped.setdefault(ptype, {}).setdefault(pgroup, []).append((lat, lng))
        
        outer = [
            grouped["outer"][k]
            for k in sorted(grouped["outer"].keys())
            if len(grouped["outer"][k]) >= 3
        ]
        inner = [
            grouped["inner"][k]
            for k in sorted(grouped["inner"].keys())
            if len(grouped["inner"][k]) >= 3
        ]
        limit_range = [
            grouped.get("limit_range", {}).get(k, [])
            for k in sorted(grouped.get("limit_range", {}).keys())
            if len(grouped.get("limit_range", {}).get(k, [])) >= 3
        ]
        return outer, inner, limit_range