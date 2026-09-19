"""Pydantic schemas for University Student operations, face reduction vectors, and student portal."""
from datetime import datetime, date
from typing import Optional, List, Literal
from pydantic import BaseModel, Field, ConfigDict, field_validator


class StudentRegisterRequest(BaseModel):
    """University Student registration request."""
    reg_no: str = Field(..., min_length=3, max_length=50, description="University Register Number (e.g. 714024104145)")
    name: str = Field(..., min_length=2, max_length=120, description="Student Full Name")
    dob: str = Field(..., description="Date of birth in YYYY-MM-DD or DD-MM-YYYY format")
    gender: Literal["Male", "Female", "Other"] = Field(..., description="Gender")
    dept: str = Field(..., min_length=2, max_length=50, description="Department code (CSE, ECE, MECH, etc.)")
    batch: str = Field(..., min_length=4, max_length=20, description="Batch e.g. 2022-2026")
    year_of_study: int = Field(1, ge=1, le=5, description="Year of study (1-4)")
    semester: int = Field(1, ge=1, le=8, description="Semester (1-8)")
    section: str = Field("A", min_length=1, max_length=10, description="Section (A, B, C)")
    parent_phone: str = Field(..., min_length=7, max_length=20, description="Parent/Guardian contact number")
    
    # Optional Academic & Personal Fields
    roll_no: Optional[str] = Field(None, max_length=50, description="Roll Number")
    email: Optional[str] = Field(None, max_length=120, description="Student Email")
    phone_number: Optional[str] = Field(None, max_length=20, description="Student Phone Number")
    blood_group: Optional[str] = Field(None, max_length=10, description="Blood Group (e.g. O+, A+)")
    degree: str = Field("B.E.", max_length=50, description="Degree (B.E., B.Tech, M.E., etc.)")
    quota: str = Field("Govt", max_length=20, description="Admission Quota (Govt, Management)")
    mentor_staff_reg_no: Optional[str] = Field(None, max_length=50, description="Assigned Class Advisor / Mentor staff reg_no")
    father_name: Optional[str] = Field(None, max_length=120, description="Father's Name")
    mother_name: Optional[str] = Field(None, max_length=120, description="Mother's Name")
    parent_email: Optional[str] = Field(None, max_length=120, description="Parent Email")
    emergency_contact: Optional[str] = Field(None, max_length=20, description="Emergency Contact Number")
    permanent_address: Optional[str] = Field(None, max_length=300, description="Permanent Address")
    city: Optional[str] = Field(None, max_length=100, description="City")
    state: str = Field("Tamil Nadu", max_length=100, description="State")
    pincode: Optional[str] = Field(None, max_length=10, description="Pincode")
    
    # Biometric Face Images (Base64 strings for 3 angles: front, left, right)
    images_base64: List[str] = Field(default_factory=list, description="List of base64-encoded face images")
    custom_password: Optional[str] = Field(None, min_length=6, description="Optional custom initial password")
    overwrite: bool = Field(False, description="Allow overwriting existing student face embeddings")

    @field_validator("reg_no", "name", "dept", "batch", "parent_phone", mode="before")
    @classmethod
    def strip_strings(cls, v):
        if isinstance(v, str):
            return v.strip()
        return v


class StudentLoginRequest(BaseModel):
    """Student portal login request."""
    reg_no: str = Field(..., description="Student University Register Number")
    password: str = Field(..., min_length=1, description="Password or DOB")
    device_id: Optional[str] = Field(None, description="Optional client device UUID")


class StudentPasswordChangeRequest(BaseModel):
    """Student password update request."""
    old_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=6, max_length=64)


class StudentLeaveODApplyRequest(BaseModel):
    """On-Duty or Medical leave application."""
    request_type: Literal["ON_DUTY", "MEDICAL_LEAVE", "CASUAL_LEAVE"] = Field(...)
    start_date: str = Field(..., description="Start date (YYYY-MM-DD)")
    end_date: str = Field(..., description="End date (YYYY-MM-DD)")
    session_half: Literal["FULL_DAY", "FN", "AN"] = Field("FULL_DAY")
    reason: str = Field(..., min_length=5, max_length=500)
    document_proof_url: Optional[str] = Field(None)


class StudentProfileResponse(BaseModel):
    """Detailed student profile."""
    reg_no: str
    roll_no: Optional[str] = None
    name: str
    email: Optional[str] = None
    phone_number: Optional[str] = None
    dob: str
    gender: str
    blood_group: Optional[str] = None
    degree: str
    dept: str
    batch: str
    year_of_study: int
    semester: int
    section: str
    quota: str
    mentor_staff_reg_no: Optional[str] = None
    mentor_name: Optional[str] = None
    parent_phone: str
    has_face_registered: bool = False
    first_time_login: bool = False
    suspended: bool = False
    created_at: Optional[str] = None
