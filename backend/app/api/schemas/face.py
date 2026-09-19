from datetime import datetime
from typing import Optional, List, Literal
from pydantic import BaseModel, Field, ConfigDict, field_validator
from .common import APIResponse

# Face registration schemas


class FaceRegisterRequest(BaseModel):
    """Face registration request."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "reg_no": "2020CS001",
                    "force": False
                }
            ]
        }
    )

    reg_no: str = Field(..., min_length=1, max_length=50, description="User registration number to register")
    force: bool = Field(False, description="Force re-registration even if already registered")

    @field_validator("reg_no", mode="before")
    @classmethod
    def strip_reg_no(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v


class FaceStatusResponse(BaseModel):
    """Face registration status."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "registered": True,
                    "samples_count": 5,
                    "last_updated": "2024-01-15T10:30:00Z",
                    "can_reregister": False
                }
            ]
        }
    )

    registered: bool = Field(..., description="Whether face is currently registered")
    samples_count: int = Field(..., ge=0, description="Number of face samples stored")
    last_updated: Optional[datetime] = Field(None, description="Timestamp of last update")
    can_reregister: bool = Field(..., description="Whether user can re-register face")

    model_config = ConfigDict(
        from_attributes=True,
        json_schema_extra={
            "examples": [
                {
                    "registered": True,
                    "samples_count": 5,
                    "last_updated": "2024-01-15T10:30:00Z",
                    "can_reregister": False
                }
            ]
        }
    )


class FaceVerifyRequest(BaseModel):
    """Face verification request."""
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "reg_no": "2020CS001"
                }
            ]
        }
    )

    reg_no: str = Field(..., min_length=1, max_length=50, description="User registration number to verify")

    @field_validator("reg_no", mode="before")
    @classmethod
    def strip_reg_no(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v


class FaceMatch(BaseModel):
    """Face matching result."""
    reg_no: str = Field(..., description="Matched user registration number")
    name: str = Field(..., description="Matched user name")
    confidence: float = Field(..., ge=0, le=1, description="Recognition confidence (0-1)")
    similarity: float = Field(..., ge=0, le=1, description="Similarity score (0-1)")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "reg_no": "2020CS001",
                    "name": "John Doe",
                    "confidence": 0.92,
                    "similarity": 0.88
                }
            ]
        }
    )


class FaceVerifyResponse(APIResponse):
    """Face verification response with matches."""
    matches: Optional[List[FaceMatch]] = Field(None, description="List of matching users")

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "success": True,
                    "message": "Face verified successfully",
                    "data": None,
                    "error": None,
                    "timestamp": "2024-01-15T14:30:00Z",
                    "matches": [
                        {
                            "reg_no": "2020CS001",
                            "name": "John Doe",
                            "confidence": 0.92,
                            "similarity": 0.88
                        }
                    ]
                }
            ]
        }
    )


class CaptureRequest(BaseModel):
    """Face capture request (for mobile/web integration)."""
    reg_no: str = Field(..., min_length=1, max_length=50, description="User registration number")
    image_base64: str = Field(..., description="Base64 encoded face image")
    force: bool = Field(False, description="Override existing registration")

    @field_validator("reg_no", mode="before")
    @classmethod
    def strip_reg_no(cls, v: str) -> str:
        if isinstance(v, str):
            return v.strip()
        return v
