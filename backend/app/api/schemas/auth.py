from datetime import datetime
from typing import Optional, Literal
from pydantic import BaseModel, Field, ConfigDict, field_validator

# Import in same file to avoid circular imports
# These would normally come from a separate user schema


class UserInfo(BaseModel):
    """Basic user information for authentication responses."""
    reg_no: str = Field(..., description="User registration number", examples=["2020CS001"])
    name: str = Field(..., description="User full name", examples=["John Doe"])
    dept: str = Field(..., description="Department identifier", examples=["CSE"])
    role: Literal['admin', 'hod', 'staff', 'student'] = Field(..., description="User role")
    face_registered: bool = Field(False, description="Whether face biometric is registered")

    model_config = ConfigDict(from_attributes=True)


class LoginRequest(BaseModel):
    """User login request schema."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "username": "2020CS001",
                    "password": "secure_password_123"
                }
            ]
        }
    )

    username: str = Field(..., description="Username or registration number", examples=["2020CS001", "admin"])
    password: str = Field(..., description="User password", examples=["secure_password_123"])

    @field_validator("username", "password", mode="before")
    @classmethod
    def strip_strings(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v


class LoginResponse(BaseModel):
    """Successful login response with JWT token."""
    model_config = ConfigDict(from_attributes=True)

    token: str = Field(..., description="JWT authentication token", examples=["eyJhbGciOiJIUzI1NiIs..."])
    user: UserInfo = Field(..., description="Authenticated user information")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                    "user": {
                        "reg_no": "2020CS001",
                        "name": "John Doe",
                        "dept": "CSE",
                        "role": "staff",
                        "face_registered": True
                    }
                }
            ]
        }
    )


class TokenData(BaseModel):
    """JWT token claims for internal use."""
    reg_no: str = Field(..., description="User registration number from token")
    role: str = Field(..., description="User role from token")
    name: str = Field(..., description="User name from token")

    model_config = ConfigDict(from_attributes=True)
