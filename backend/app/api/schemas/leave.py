from datetime import date
from typing import Optional, List, Literal
from pydantic import BaseModel, Field, ConfigDict, field_validator, model_validator
from .common import APIResponse, PaginatedResponse

# Leave management schemas


class LeaveRequestCreate(BaseModel):
    """Create leave request."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "leave_type": "casual",
                    "start_date": "2024-01-20",
                    "end_date": "2024-01-22",
                    "reason": "Personal work at home"
                }
            ]
        }
    )

    leave_type: Literal['casual', 'earned', 'od', 'sick'] = Field(..., description="Type of leave")
    start_date: date = Field(..., description="Leave start date")
    end_date: date = Field(..., description="Leave end date")
    reason: str = Field(..., min_length=10, max_length=1000, description="Reason for leave")

    @field_validator("reason", mode="before")
    @classmethod
    def strip_reason(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v

    @model_validator(mode="after")
    def validate_dates(self) -> "LeaveRequestCreate":
        if self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        return self

    @model_validator(mode="after")
    def validate_reason_length(self) -> "LeaveRequestCreate":
        # Additional check for min length after strip
        reason_stripped = self.reason.strip() if self.reason else ""
        if len(reason_stripped) < 10:
            raise ValueError("reason must be at least 10 characters")
        return self


class LeaveRequestUpdate(BaseModel):
    """Update leave request status (admin only)."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "status": "approved",
                    "admin_comment": "Approved as requested"
                }
            ]
        }
    )

    status: Literal['pending', 'approved', 'rejected'] = Field(..., description="Updated status")
    admin_comment: Optional[str] = Field(None, min_length=1, max_length=500, description="Admin comment")

    @field_validator("admin_comment", mode="before")
    @classmethod
    def strip_comment(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and isinstance(v, str):
            return v.strip() if v.strip() else None
        return v


class LeaveRequestResponse(BaseModel):
    """Leave request response with full details."""
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(..., description="Leave request ID")
    user_reg_no: str = Field(..., description="User registration number")
    user_name: str = Field(..., description="User full name")
    dept: str = Field(..., description="Department code")
    leave_type: str = Field(..., description="Leave type")
    start_date: date = Field(..., description="Leave start date")
    end_date: date = Field(..., description="Leave end date")
    reason: str = Field(..., description="Leave reason")
    status: Literal['pending', 'approved', 'rejected'] = Field(..., description="Current status")
    processed_by: Optional[str] = Field(None, description="Admin who processed request")
    processed_date: Optional[date] = Field(None, description="Date when processed")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "id": 1,
                    "user_reg_no": "2020CS001",
                    "user_name": "John Doe",
                    "dept": "CSE",
                    "leave_type": "casual",
                    "start_date": "2024-01-20",
                    "end_date": "2024-01-22",
                    "reason": "Personal work",
                    "status": "pending",
                    "processed_by": None,
                    "processed_date": None
                }
            ]
        }
    )


class CLBalanceResponse(BaseModel):
    """Casual Leave balance response."""
    current_month_cl_available: int = Field(..., ge=0, description="CL available in current month")
    accumulated_cl: int = Field(..., ge=0, description="Accumulated CL from previous months")
    cl_used_current_month: int = Field(..., ge=0, description="CL used in current month")
    total_cl_available: int = Field(..., ge=0, description="Total CL available overall")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "current_month_cl_available": 5,
                    "accumulated_cl": 10,
                    "cl_used_current_month": 2,
                    "total_cl_available": 15
                }
            ]
        }
    )

    @model_validator(mode="after")
    def validate_totals(self) -> "CLBalanceResponse":
        if self.current_month_cl_available + self.accumulated_cl != self.total_cl_available:
            raise ValueError("CL totals mismatch")
        if self.accumulated_cl < self.cl_used_current_month:
            raise ValueError("Used CL cannot exceed accumulated CL")
        return self


class CLAdjustRequest(BaseModel):
    """Admin request to adjust CL balance."""
    current_month_cl_available: Optional[int] = Field(None, ge=0, description="New current month CL")
    accumulated_cl: Optional[int] = Field(None, ge=0, description="New accumulated CL")
    used_cl: Optional[int] = Field(None, ge=0, description="CL used this month")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "current_month_cl_available": 10,
                    "accumulated_cl": 20,
                    "used_cl": 5
                }
            ]
        }
    )

    @model_validator(mode="after")
    def validate_at_least_one(self) -> "CLAdjustRequest":
        if all([
            self.current_month_cl_available is None,
            self.accumulated_cl is None,
            self.used_cl is None
        ]):
            raise ValueError("At least one field must be provided")
        return self


class LeaveStats(BaseModel):
    """Leave statistics for dashboard."""
    total_requests: int = Field(..., ge=0)
    pending: int = Field(..., ge=0)
    approved: int = Field(..., ge=0)
    rejected: int = Field(..., ge=0)
    this_month: int = Field(..., ge=0, description="Leave requests this month")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "total_requests": 25,
                    "pending": 5,
                    "approved": 15,
                    "rejected": 5,
                    "this_month": 8
                }
            ]
        }
    )
