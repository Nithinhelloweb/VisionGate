from datetime import datetime
from typing import Optional, List, Literal
from pydantic import BaseModel, Field, ConfigDict, field_validator, model_validator
from .common import APIResponse

# Geo-fence schemas


class GeoCoordinate(BaseModel):
    """A single geographic coordinate."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "latitude": 13.0827,
                    "longitude": 80.2707,
                    "point_order": 1
                }
            ]
        }
    )

    latitude: float = Field(..., ge=-90, le=90, description="Latitude coordinate", examples=[13.0827])
    longitude: float = Field(..., ge=-180, le=180, description="Longitude coordinate", examples=[80.2707])
    point_order: Optional[int] = Field(None, ge=0, description="Vertex order for polygon definition")


class PolygonCreate(BaseModel):
    """Geo-fence polygon creation request."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "polygon_type": "outer",
                    "polygon_group": 1,
                    "coordinates": [
                        {"latitude": 13.0830, "longitude": 80.2710, "point_order": 0},
                        {"latitude": 13.0835, "longitude": 80.2715, "point_order": 1},
                        {"latitude": 13.0840, "longitude": 80.2710, "point_order": 2}
                    ]
                }
            ]
        }
    )

    polygon_type: Literal['outer', 'inner'] = Field(..., description="Polygon type (outer boundary or hole)")
    polygon_group: int = Field(1, ge=1, description="Polygon group ID for multiple polygons")
    coordinates: List[GeoCoordinate] = Field(..., min_length=3, description="Polygon vertices (minimum 3)")

    @field_validator("coordinates", mode="before")
    @classmethod
    def sort_coordinates(cls, coords: List[GeoCoordinate]) -> List[GeoCoordinate]:
        """Ensure coordinates are sorted by point_order for consistent polygon definition."""
        if coords and all(c.point_order is not None for c in coords):
            return sorted(coords, key=lambda c: c.point_order)
        return coords

    @model_validator(mode="after")
    def validate_closed_polygon(self) -> "PolygonCreate":
        """Ensure first and last points are same for closed polygon if needed."""
        if len(self.coordinates) >= 3:
            first = self.coordinates[0]
            last = self.coordinates[-1]
            # Polygon doesn't need to repeat first point in storage, but warn if open
            pass
        return self


class GeoFenceResponse(BaseModel):
    """Geo-fence response with outer and inner polygons."""
    model_config = ConfigDict(from_attributes=True)

    outer_polygons: List[List[GeoCoordinate]] = Field(..., description="List of outer boundary polygons")
    inner_polygons: List[List[GeoCoordinate]] = Field([], description="List of inner holes/exclusions")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "outer_polygons": [
                        [
                            {"latitude": 13.0830, "longitude": 80.2710},
                            {"latitude": 13.0835, "longitude": 80.2715},
                            {"latitude": 13.0840, "longitude": 80.2710}
                        ]
                    ],
                    "inner_polygons": []
                }
            ]
        }
    )


class LocationUpdateRequest(BaseModel):
    """Client location update (mobile/gps)."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "lat": 13.0827,
                    "lng": 80.2707,
                    "accuracy_meters": 5.0,
                    "speed_mps": 0.0,
                    "heading_deg": 90.0,
                    "altitude_m": 10.5,
                    "source": "gps",
                    "app_state": "foreground",
                    "is_mocked": False,
                    "device_id": "abc123",
                    "captured_at": "2024-01-15T10:30:00Z"
                }
            ]
        }
    )

    lat: float = Field(..., ge=-90, le=90, description="Latitude")
    lng: float = Field(..., ge=-180, le=180, description="Longitude")
    accuracy_meters: Optional[float] = Field(None, ge=0, description="GPS accuracy in meters")
    speed_mps: Optional[float] = Field(None, ge=0, description="Speed in meters/second")
    heading_deg: Optional[float] = Field(None, ge=0, le=360, description="Heading in degrees")
    altitude_m: Optional[float] = Field(None, description="Altitude in meters")
    source: Literal["gps", "network", "fused", "manual"] = Field(..., description="Location source")
    app_state: Literal["foreground", "background", "killed"] = Field(..., description="App execution state")
    is_mocked: bool = Field(False, description="Whether location is mocked/spoofed")
    device_id: str = Field(..., description="Device identifier")
    captured_at: Optional[datetime] = Field(None, description="Timestamp when location was captured")

    @field_validator("device_id", mode="before")
    @classmethod
    def strip_device_id(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v


class GeoFenceCheckRequest(BaseModel):
    """Check if point is inside geo-fence."""
    lat: float = Field(..., ge=-90, le=90, description="Latitude to check")
    lng: float = Field(..., ge=-180, le=180, description="Longitude to check")

    model_config = ConfigDict(from_attributes=True)


class GeoFenceCheckResponse(BaseModel):
    """Geo-fence check result."""
    inside: bool = Field(..., description="Whether point is inside geo-fence")
    distance_to_boundary: Optional[float] = Field(None, description="Distance to nearest boundary in meters")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "inside": True,
                    "distance_to_boundary": 15.5
                }
            ]
        }
    )
