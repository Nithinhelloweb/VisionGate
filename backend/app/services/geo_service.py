"""Geo service for geo-fencing, VPN detection, and location validation."""
import asyncio
import ipaddress
import logging
from typing import Optional, Tuple, Dict, Any, List

from app.database.repositories.geo_repository import GeoRepository
from app.config import geo_config, settings

logger = logging.getLogger(__name__)


class GeoService:
    def __init__(self, geo_repo: GeoRepository):
        self.geo_repo = geo_repo
        self._outer_polygons: List[List[Tuple[float, float]]] = []
        self._inner_polygons: List[List[Tuple[float, float]]] = []
        self._limit_range_polygons: List[List[Tuple[float, float]]] = []
        self._lock = asyncio.Lock()

    async def load_geo_fence(self, force_reload: bool = False) -> None:
        """Load geo-fence polygons from DB or defaults."""
        async with self._lock:
            if not self._outer_polygons or force_reload:
                outer, inner, limit_range = await self.geo_repo.get_geo_fence_polygons()
                if not outer:
                    outer = [geo_config.get_default_outer()]
                    inner = [geo_config.get_default_inner()]
                    limit_range = []
                self._outer_polygons = outer
                self._inner_polygons = inner
                self._limit_range_polygons = limit_range
                logger.info(f"Loaded geo-fence: {len(outer)} outer, {len(inner)} inner, {len(limit_range)} limit range polygons")

    def is_point_in_polygon(self, lat: float, lng: float, polygon: List[Tuple[float, float]]) -> bool:
        """
        Ray-casting algorithm to check if point is inside polygon.
        lat=y, lng=x for ray-casting calculation.
        """
        if len(polygon) < 3:
            return False
        
        inside = False
        n = len(polygon)
        for i in range(n):
            j = (i + 1) % n
            yi, xi = polygon[i]
            yj, xj = polygon[j]
            
            if (yi > lat) != (yj > lat):
                dy = yj - yi
                if abs(dy) < 1e-7:
                    continue
                t = (lat - yi) / dy
                x_intersect = xi + t * (xj - xi)
                if lng < x_intersect:
                    inside = not inside
        return inside

    def is_inside_geo_fence(self, lat: float, lng: float) -> bool:
        """
        Check if point is inside outer but outside all inner polygons.
        Returns True if no geo-fence is configured (allows by default).
        """
        if not self._outer_polygons:
            self.logger.warning("No geo-fence configured - allowing all locations")
            return True
        
        in_outer = any(
            self.is_point_in_polygon(lat, lng, poly) 
            for poly in self._outer_polygons
        )
        if not in_outer:
            return False
        
        for inner_poly in self._inner_polygons:
            if self.is_point_in_polygon(lat, lng, inner_poly):
                return False
        
        return True

    def is_vpn_ip(self, ip_str: str) -> bool:
        """Check if IP is in known VPN/hosting ranges."""
        try:
            ip = ipaddress.ip_address(ip_str)
            cloud_ranges = [
                ipaddress.ip_network("3.0.0.0/8"),
                ipaddress.ip_network("13.0.0.0/8"),
                ipaddress.ip_network("34.0.0.0/8"),
                ipaddress.ip_network("35.0.0.0/8"),
                ipaddress.ip_network("52.0.0.0/8"),
                ipaddress.ip_network("104.16.0.0/12"),
                ipaddress.ip_network("172.64.0.0/13"),
                ipaddress.ip_network("185.199.108.0/22"),
                ipaddress.ip_network("103.192.152.0/22"),
                ipaddress.ip_network("185.220.101.0/24"),
                ipaddress.ip_network("209.222.18.0/24"),
                ipaddress.ip_network("198.143.200.0/23"),
                ipaddress.ip_network("192.71.192.0/22"),
                ipaddress.ip_network("193.32.248.0/22"),
                ipaddress.ip_network("149.102.0.0/16"),
            ]
            for rng in cloud_ranges:
                if ip in rng:
                    return True
        except ValueError:
            pass
        return False

    async def check_attendance_permission(
        self,
        lat: float,
        lng: float,
        platform: str = "mobile"
    ) -> Tuple[bool, Optional[str]]:
        """
        Check if attendance is allowed at given location.
        Returns: (allowed, reason_if_denied)
        """
        if not settings.ENFORCE_GEO_FENCE:
            return True, None
        
        await self.load_geo_fence()
        
        if platform == "web":
            if not self._outer_polygons:
                return True, None
        
        if not self.is_inside_geo_fence(lat, lng):
            return False, "Outside allowed geofence area"
        
        return True, None

    def check_vpn_permission(self, client_ip: str) -> Tuple[bool, Optional[str]]:
        """
        Check if client IP is allowed (not VPN blocked).
        Returns: (allowed, reason_if_denied)
        """
        if not settings.ENFORCE_VPN_BLOCKING:
            return True, None
        
        if self.is_vpn_ip(client_ip):
            return False, f"VPN/proxy connection detected from {client_ip}"
        
        return True, None

    async def validate_location_and_ip(
        self,
        lat: Optional[float],
        lng: Optional[float],
        client_ip: str,
        platform: str = "mobile"
    ) -> Dict[str, Any]:
        """
        Combined location and IP validation.
        Returns validation result with details.
        """
        results = {
            "location_valid": True,
            "ip_valid": True,
            "errors": []
        }
        
        if lat is not None and lng is not None:
            allowed, reason = await self.check_attendance_permission(lat, lng, platform)
            if not allowed:
                results["location_valid"] = False
                results["errors"].append({"type": "location", "message": reason})
        
        ip_allowed, ip_reason = self.check_vpn_permission(client_ip)
        if not ip_allowed:
            results["ip_valid"] = False
            results["errors"].append({"type": "ip", "message": ip_reason})
        
        results["overall_valid"] = results["location_valid"] and results["ip_valid"]
        return results

    async def get_geo_fence_public(self) -> Dict[str, Any]:
        """Get geo-fence coordinates for public access (mobile app)."""
        await self.load_geo_fence()
        
        outer_polygons_json = [
            [[float(p[0]), float(p[1])] for p in poly]
            for poly in (self._outer_polygons or [])
        ]
        inner_polygons_json = [
            [[float(p[0]), float(p[1])] for p in poly]
            for poly in (self._inner_polygons or [])
        ]
        limit_range_polygons_json = [
            [[float(p[0]), float(p[1])] for p in poly]
            for poly in (self._limit_range_polygons or [])
        ]
        
        outer_coords = outer_polygons_json[0] if outer_polygons_json else []
        inner_coords = inner_polygons_json[0] if inner_polygons_json else []
        limit_range_coords = limit_range_polygons_json[0] if limit_range_polygons_json else []
        
        return {
            "success": True,
            "outer_polygon": outer_coords,
            "inner_polygon": inner_coords,
            "limit_range_polygon": limit_range_coords,
            "outer_polygons": outer_polygons_json,
            "inner_polygons": inner_polygons_json,
            "limit_range_polygons": limit_range_polygons_json,
        }

    def calculate_distance(
        self,
        lat1: float,
        lng1: float,
        lat2: float,
        lng2: float
    ) -> float:
        """
        Calculate distance between two points in meters using Haversine formula.
        """
        import math
        
        R = 6371000
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lng2 - lng1)
        
        a = math.sin(delta_phi / 2) ** 2 + \
            math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        
        return R * c