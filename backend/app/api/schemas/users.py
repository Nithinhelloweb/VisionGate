from datetime import datetime, date
from typing import Optional, List
from pydantic import BaseModel, Field, ConfigDict, EmailStr, field_validator
from pydantic.types import Json
from .common import APIResponse, ErrorResponse, PaginatedResponse

# Note: These schemas would typically import from a shared models module
# For now, defining minimal user structures inline


class UserBase(BaseModel):
    """Base user fields."""
    reg_no: str = Field(..., min_length=1, max_length=50, description="Registration number", examples=["2020CS001"])
    name: str = Field(..., min_length=1, max_length=120, description="Full name", examples=["John Doe"])
    dept: str = Field(..., min_length=1, max_length=50, description="Department code", examples=["CSE"])
    role: str = Field(..., description="User role", examples=["staff", "student", "admin"])

    model_config = ConfigDict(from_attributes=True)

    @field_validator("name", "dept", mode="before")
    @classmethod
    def strip_strings(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v


class UserCreate(UserBase):
    """User creation request (for admin use)."""
    username: str = Field(..., min_length=3, max_length=120, description="Login username")
    password: str = Field(..., min_length=6, description="User password")

    @field_validator("password", mode="before")
    @classmethod
    def strip_password(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v


class UserUpdate(BaseModel):
    """User update request (all fields optional)."""
    name: Optional[str] = Field(None, min_length=1, max_length=120, description="Updated full name")
    dept: Optional[str] = Field(None, min_length=1, max_length=50, description="Updated department")
    role: Optional[str] = Field(None, description="Updated role")
    can_reregister: Optional[bool] = Field(None, description="Allow face re-registration")

    model_config = ConfigDict(from_attributes=True)

    @field_validator("name", "dept", mode="before")
    @classmethod
    def strip_strings(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and isinstance(v, str):
            return v.strip()
        return v


class UserResponse(UserBase):
    """User response object."""
    id: int = Field(..., description="Internal user ID")
    created_at: datetime = Field(..., description="Account creation timestamp")
    embedding_registered: bool = Field(..., description="Whether face embedding is registered")
    can_reregister: Optional[bool] = Field(None, description="Permission to re-register face")

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "examples": [
                {
                    "id": 1,
                    "username": "2020CS001",
                    "reg_no": "2020CS001",
                    "name": "John Doe",
                    "dept": "CSE",
                    "role": "staff",
                    "created_at": "2024-01-15T10:30:00",
                    "embedding_registered": True,
                    "can_reregister": False
                }
            ]
        }
    )


class UserListResponse(APIResponse):
    """Paginated user list response."""
    data: Optional[List[UserResponse]] = Field(None, description="List of users")
    total: int = Field(..., ge=0, description="Total count of users")
    page: int = Field(..., ge=1, description="Current page number")
    per_page: int = Field(..., ge=1, description="Items per page")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "success": True,
                    "message": "Users retrieved",
                    "data": [
                        {
                            "id": 1,
                            "username": "2020CS001",
                            "reg_no": "2020CS001",
                            "name": "John Doe",
                            "dept": "CSE",
                            "role": "staff",
                            "created_at": "2024-01-15T10:30:00",
                            "embedding_registered": True
                        }
                    ],
                    "error": None,
                    "timestamp": "2024-01-15T10:30:00",
                    "total": 1,
                    "page": 1,
                    "per_page": 20
                }
            ]
        }
    )


# Other staff schemas (different from regular users)


class OtherStaffCreate(BaseModel):
    """Additional staff creation with DOB."""
    username: str = Field(..., min_length=3, max_length=120, description="Login username")
    password: str = Field(..., min_length=6, description="User password")
    reg_no: str = Field(..., min_length=1, max_length=50, description="Registration number")
    name: str = Field(..., min_length=1, max_length=120, description="Full name")
    dept: str = Field(..., min_length=1, max_length=50, description="Department code")
    role: str = Field(..., description="User role")
    dob: date = Field(..., description="Date of birth")

    model_config = ConfigDict(from_attributes=True)

    @field_validator("name", "dept", mode="before")
    @classmethod
    def strip_strings(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v

    @field_validator("password", mode="before")
    @classmethod
    def strip_password(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v


class OtherStaffResponse(BaseModel):
    """Other staff response including DOB."""
    id: int = Field(..., description="Internal user ID")
    username: str = Field(..., description="Login username")
    reg_no: str = Field(..., description="Registration number")
    name: str = Field(..., description="Full name")
    dept: str = Field(..., description="Department code")
    role: str = Field(..., description="User role")
    dob: date = Field(..., description="Date of birth")
    created_at: datetime = Field(..., description="Account creation timestamp")
    embedding_registered: bool = Field(..., description="Whether face embedding is registered")
    can_reregister: Optional[bool] = Field(None, description="Permission to re-register face")

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "examples": [
                {
                    "id": 2,
                    "username": "otherstaff001",
                    "reg_no": "OTHER001",
                    "name": "Jane Smith",
                    "dept": "CSE",
                    "role": "staff",
                    "dob": "1990-05-15",
                    "created_at": "2024-01-15T10:30:00",
                    "embedding_registered": False,
                    "can_reregister": True
                }
            ]
        }
    )
