from datetime import datetime
from typing import Optional, TypeVar, Generic, List
from pydantic import BaseModel, Field, ConfigDict, field_validator

T = TypeVar("T")


class APIResponse(BaseModel, Generic[T]):
    """Generic API response wrapper for all endpoints."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "success": True,
                    "message": "Operation successful",
                    "data": {"id": 1, "name": "Example"},
                    "error": None,
                    "timestamp": "2024-01-15T10:30:00"
                }
            ]
        }
    )

    success: bool = Field(..., description="Indicates if the request was successful", examples=[True, False])
    message: str = Field(..., description="Human-readable response message", examples=["Operation successful", "Invalid input"])
    data: Optional[T] = Field(None, description="Response payload data")
    error: Optional[str] = Field(None, description="Error message if request failed")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="Response timestamp")

    @field_validator("message", "error", mode="before")
    @classmethod
    def strip_strings(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and isinstance(v, str):
            return v.strip()
        return v


class ErrorResponse(BaseModel):
    """Standard error response schema."""
    error_code: str = Field(..., description="Machine-readable error code")
    detail: str = Field(..., description="Human-readable error description")


class PaginationParams(BaseModel):
    """Pagination query parameters."""
    page: int = Field(1, ge=1, description="Page number (1-indexed)")
    per_page: int = Field(20, ge=1, le=100, description="Items per page")

    @property
    def offset(self) -> int:
        return (self.page - 1) * self.per_page


class PaginatedResponse(APIResponse[T], Generic[T]):
    """API response with pagination information."""
    pagination: PaginationParams
    total: int = Field(..., ge=0)
    pages: int = Field(..., ge=0)


class DateRangeRequest(BaseModel):
    """Date range filter."""
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None

    from pydantic import model_validator

    @model_validator(mode="after")
    def validate_date_range(self) -> "DateRangeRequest":
        if self.start_date and self.end_date and self.end_date < self.start_date:
            raise ValueError("end_date must be on or after start_date")
        return self
