import datetime as dt
from typing import Optional, List, Literal, Dict, Any
from decimal import Decimal
from pydantic import BaseModel, Field, ConfigDict, field_validator

# Test minimal module
class Coordinates(BaseModel):
    """GPS coordinates."""
    latitude: float = Field(..., ge=-90, le=90, description="Latitude coordinate", examples=[13.0827])
    longitude: float = Field(..., ge=-180, le=180, description="Longitude coordinate", examples=[80.2707])

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "latitude": 13.0827,
                    "longitude": 80.2707
                }
            ]
        }
    )

class AttendanceMarkRequest(BaseModel):
    """Attendance marking request."""
    reg_no: str = Field(..., min_length=1, max_length=50, description="User registration number")
    client_lat: Optional[float] = Field(None, ge=-90, le=90, description="Client GPS latitude")
    client_lng: Optional[float] = Field(None, ge=-180, le=180, description="Client GPS longitude")
    client_platform: Optional[Literal["web", "mobile"]] = Field(None, description="Client platform type")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "reg_no": "2020CS001",
                    "client_lat": 13.0827,
                    "client_lng": 80.2707,
                    "client_platform": "web"
                }
            ]
        }
    )

    @field_validator("reg_no", mode="before")
    @classmethod
    def strip_strings(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v

class AttendanceMarkResponse(BaseModel):
    """Attendance marking response."""
    attendance_id: int = Field(..., description="Unique attendance record ID")
    timestamp: dt.datetime = Field(..., description="Attendance timestamp (UTC)")
    confidence: float = Field(..., ge=0, le=1, description="Face recognition confidence score")
    mode: Literal["insightface", "fallback"] = Field(..., description="Detection method used")

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "examples": [
                {
                    "attendance_id": 123,
                    "timestamp": "2024-01-15T14:30:00Z",
                    "confidence": 0.92,
                    "mode": "insightface"
                }
            ]
        }
    )

class AttendanceRecord(BaseModel):
    """Single attendance record."""
    id: int = Field(..., description="Attendance record ID")
    reg_no: str = Field(..., description="User registration number")
    name: str = Field(..., description="User full name")
    dept: str = Field(..., description="Department code")
    timestamp: dt.datetime = Field(..., description="Check-in timestamp")
    error_message: Optional[str] = Field(None, description="Error message if any")

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "examples": [
                {
                    "id": 1,
                    "reg_no": "2020CS001",
                    "name": "John Doe",
                    "dept": "CSE",
                    "timestamp": "2024-01-15T09:00:00Z",
                    "error_message": None
                }
            ]
        }
    )

class DailyStatusResponse(BaseModel):
    """Daily attendance status for a user."""
    date: dt.date = Field(..., description="Date of status")
    status: Literal["present", "absent", "half_day", "leave", "holiday"] = Field(..., description="Attendance status")
    leave_type: Optional[Literal["casual", "earned", "od", "sick"]] = Field(None, description="Leave type if on leave")
    leave_request_id: Optional[int] = Field(None, description="Associated leave request ID")
    attendance_value: Optional[Decimal] = Field(None, ge=Decimal("0.0"), le=Decimal("1.0"), description="Attendance value (0.0, 0.5, or 1.0)")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "date": "2024-01-15",
                    "status": "present",
                    "leave_type": None,
                    "leave_request_id": None,
                    "attendance_value": 1.0
                }
            ]
        }
    )


class AttendanceValueSummary(BaseModel):
    """Attendance value summary for a period."""
    reg_no: str = Field(..., description="User registration number")
    name: str = Field(..., description="User full name")
    dept: str = Field(..., description="Department")
    start_date: dt.date = Field(..., description="Start date of period")
    end_date: dt.date = Field(..., description="End date of period")
    total_attendance_value: Decimal = Field(..., ge=Decimal("0.0"), description="Total attendance value accumulated")
    total_working_days: int = Field(..., ge=0, description="Total working days in period")
    attendance_percentage: Decimal = Field(..., ge=Decimal("0.0"), le=Decimal("100.0"), description="Attendance percentage")
    full_days: int = Field(..., ge=0, description="Number of full days (1.0)")
    half_days: int = Field(..., ge=0, description="Number of half days (0.5)")
    absent_days: int = Field(..., ge=0, description="Number of absent days (0.0)")
    leave_days: int = Field(..., ge=0, description="Number of leave days")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "reg_no": "2020CS001",
                    "name": "John Doe",
                    "dept": "CSE",
                    "start_date": "2024-01-01",
                    "end_date": "2024-01-31",
                    "total_attendance_value": 22.5,
                    "total_working_days": 22,
                    "attendance_percentage": 102.27,
                    "full_days": 20,
                    "half_days": 5,
                    "absent_days": 2,
                    "leave_days": 1
                }
            ]
        }
    )


class HalfDayReport(BaseModel):
    """Half-day attendance report for a specific date."""
    date: dt.date = Field(..., description="Report date")
    total_users: int = Field(..., description="Total number of users")
    full_day_present: int = Field(..., description="Users with full day present")
    first_half_only: int = Field(..., description="Users present only in first half")
    second_half_only: int = Field(..., description="Users present only in second half")
    full_day_absent: int = Field(..., description="Users absent full day")
    on_leave: int = Field(..., description="Users on leave")
    details: List[Dict[str, Any]] = Field(default_factory=list, description="Detailed breakdown per user")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "date": "2024-01-15",
                    "total_users": 50,
                    "full_day_present": 40,
                    "first_half_only": 3,
                    "second_half_only": 2,
                    "full_day_absent": 3,
                    "on_leave": 2,
                    "details": []
                }
            ]
        }
    )
