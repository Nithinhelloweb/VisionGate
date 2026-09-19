from typing import Optional, List, Literal
from pydantic import BaseModel, Field, ConfigDict, model_validator
from datetime import datetime
from .common import APIResponse

# Admin schemas


class AppSettingsUpdate(BaseModel):
    """Update application settings."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "allow_any_network": False,
                    "college_ssid": "CAMPUS_WIFI",
                    "enforce_geo_fence": True,
                    "enforce_app_geo_fence": True,
                    "enforce_vpn_blocking": True
                }
            ]
        }
    )

    allow_any_network: bool = Field(..., description="Allow any network or restrict to SSID")
    college_ssid: str = Field(..., description="Approved WiFi SSID")
    enforce_geo_fence: bool = Field(..., description="Enforce GPS geo-fence")
    enforce_app_geo_fence: bool = Field(..., description="Use app-based geo-fence (client-side)")
    enforce_vpn_blocking: bool = Field(..., description="Block VPN connections")

    @field_validator("college_ssid", mode="before")
    @classmethod
    def strip_ssid(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v


class AppSettingsResponse(BaseModel):
    """Application settings response."""
    model_config = ConfigDict(from_attributes=True)

    allow_any_network: bool = Field(..., description="Allow any network connection")
    college_ssid: str = Field(..., description="Approved campus WiFi SSID")
    enforce_geo_fence: bool = Field(..., description="GPS geo-fence enforcement enabled")
    enforce_app_geo_fence: bool = Field(..., description="Client geo-face enabled")
    enforce_vpn_blocking: bool = Field(..., description="VPN blocking enabled")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "allow_any_network": False,
                    "college_ssid": "CAMPUS_WIFI",
                    "enforce_geo_fence": True,
                    "enforce_app_geo_fence": True,
                    "enforce_vpn_blocking": True
                }
            ]
        }
    )


class DashboardStats(BaseModel):
    """Dashboard statistics."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "total_staff": 150,
                    "present_today": 142,
                    "absent_today": 8,
                    "leave_pending": 12,
                    "geo_fence_violations": 3
                }
            ]
        }
    )

    total_staff: int = Field(..., ge=0, description="Total number of staff members")
    present_today: int = Field(..., ge=0, description="Staff present today")
    absent_today: int = Field(..., ge=0, description="Staff absent today")
    leave_pending: int = Field(..., ge=0, description="Pending leave requests")
    geo_fence_violations: int = Field(..., ge=0, description="Geo-fence violations today")

    @model_validator(mode="after")
    def validate_absent_count(self) -> "DashboardStats":
        if self.absent_today > self.total_staff:
            raise ValueError("absent_today cannot exceed total_staff")
        if self.present_today + self.absent_today > self.total_staff:
            raise ValueError("present + absent cannot exceed total staff")
        return self


class SystemStatus(BaseModel):
    """System health status."""
    model_config = ConfigDict(from_attributes=True)

    db_connected: bool = Field(..., description="Database connection status")
    redis_connected: bool = Field(..., description="Redis connection status")
    insightface_loaded: bool = Field(..., description="InsightFace model loaded")
    fallback_mode: bool = Field(..., description="Running in fallback mode")
    uptime_seconds: int = Field(..., ge=0, description="System uptime in seconds")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "db_connected": True,
                    "redis_connected": True,
                    "insightface_loaded": True,
                    "fallback_mode": False,
                    "uptime_seconds": 86400
                }
            ]
        }
    )


class AuditLogResponse(BaseModel):
    """Audit log entry."""
    id: int = Field(..., description="Audit log ID")
    user_id: Optional[int] = Field(None, description="User who performed action")
    action: str = Field(..., description="Action performed", examples=["USER_LOGIN", "FACE_REGISTER"])
    resource_type: str = Field(..., description="Resource type", examples=["user", "attendance"])
    resource_id: Optional[int] = Field(None, description="Resource ID affected")
    details: Optional[str] = Field(None, description="Additional details")
    ip_address: Optional[str] = Field(None, description="Source IP address")
    user_agent: Optional[str] = Field(None, description="User agent string")
    timestamp: datetime = Field(..., description="When action occurred")

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "examples": [
                {
                    "id": 1,
                    "user_id": 5,
                    "action": "USER_LOGIN",
                    "resource_type": "auth",
                    "resource_id": None,
                    "details": "User logged in successfully",
                    "ip_address": "192.168.1.100",
                    "user_agent": "Mozilla/5.0...",
                    "timestamp": "2024-01-15T10:30:00Z"
                }
            ]
        }
    )
