"""Dataclass models for all database tables."""
from dataclasses import dataclass
from datetime import datetime, date, time
from decimal import Decimal
from typing import Optional, List, BinaryIO
import uuid


@dataclass
class User:
    """User table model."""
    id: int
    reg_no: str
    username: str
    password_hash: str
    name: str
    dept: str
    role: str
    is_active: bool
    created_at: datetime
    updated_at: datetime
    face_embedding: Optional[bytes] = None


@dataclass
class OtherStaff:
    """Other staff table model."""
    id: int
    name: str
    dept: str
    contact_no: str
    is_active: bool
    created_at: datetime
    updated_at: datetime


@dataclass
class Attendance:
    """Attendance table model."""
    id: int
    reg_no: str
    name: str
    dept: str
    timestamp: datetime
    status: str  # 'IN', 'OUT'
    location: Optional[str] = None
    device_id: Optional[str] = None


@dataclass
class OtherStaffAttendance:
    """Other staff attendance table model."""
    id: int
    staff_id: int
    timestamp: datetime
    status: str  # 'IN', 'OUT'
    location: Optional[str] = None
    device_id: Optional[str] = None


@dataclass
class DailyAttendanceStatus:
    """Daily attendance status table model."""
    id: int
    reg_no: str
    date: date
    status: str  # 'PRESENT', 'HALF_DAY_FN', 'HALF_DAY_AN', 'ABSENT', 'ON_DUTY', 'LEAVE', 'PERMISSION', 'HOLIDAY'
    sub_status: Optional[str] = None  # 'OD_ACADEMIC', 'OD_SPORTS', 'OD_PLACEMENT', 'CL', 'CCL', 'ML', 'LOP', 'GATE_PASS'
    first_half_status: Optional[str] = None  # 'Present', 'Absent', 'Leave', 'OD', 'Pending'
    second_half_status: Optional[str] = None  # 'Present', 'Absent', 'Leave', 'OD', 'Pending'
    first_half_in_time: Optional[time] = None
    first_half_out_time: Optional[time] = None
    second_half_in_time: Optional[time] = None
    second_half_out_time: Optional[time] = None
    in_time: Optional[time] = None
    out_time: Optional[time] = None
    total_hours: Optional[Decimal] = None
    attendance_value: Optional[Decimal] = None  # 0.0, 0.5, or 1.0
    leave_type: Optional[str] = None
    absent_reason: Optional[str] = None
    document_proof_url: Optional[str] = None
    is_regularised: bool = False
    marked_by: Optional[str] = None
    updated_at: Optional[datetime] = None


@dataclass
class CasualLeave:
    """Casual leave table model."""
    id: int
    reg_no: str
    leave_date: date
    reason: str
    approved: bool
    approved_by: Optional[str] = None
    approved_at: Optional[datetime] = None
    created_at: Optional[datetime] = None


@dataclass
class LeaveRequest:
    """Leave requests table model."""
    id: int
    reg_no: str
    leave_type: str  # 'CASUAL', 'SICK', 'EARNED', etc.
    start_date: date
    end_date: date
    reason: str
    status: str  # 'PENDING', 'APPROVED', 'REJECTED'
    approved_by: Optional[str] = None
    approved_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class FaceEmbeddingSample:
    """Face embedding samples table model."""
    id: int
    reg_no: str
    source_table: str  # 'users', 'other_staff'
    embedding: bytes  # 512-dim vector
    sample_type: str  # 'ENROLLMENT', 'UPDATE'
    confidence: float
    created_at: datetime


@dataclass
class FaceTrainingRun:
    """Face training runs table model."""
    id: int
    started_at: datetime
    status: str = 'PENDING'  # 'PENDING', 'RUNNING', 'COMPLETED', 'FAILED'
    completed_at: Optional[datetime] = None
    total_samples: int = 0
    trained_embeddings: int = 0
    error_message: Optional[str] = None


@dataclass
class UserLocationLog:
    """User location logs table model."""
    id: int
    reg_no: str
    timestamp: datetime
    latitude: Decimal
    longitude: Decimal
    accuracy: Optional[Decimal] = None
    location_name: Optional[str] = None


@dataclass
class UserLatestLocation:
    """User latest locations table model."""
    reg_no: str
    latitude: Decimal
    longitude: Decimal
    timestamp: datetime
    location_name: Optional[str] = None
    accuracy: Optional[Decimal] = None


@dataclass
class GeoFenceCoordinateV2:
    """Geo fence coordinates v2 table model."""
    id: int
    fence_name: str
    latitude: Decimal
    longitude: Decimal
    radius_meters: int
    is_active: bool
    created_at: datetime
    updated_at: datetime


@dataclass
class AttendanceDurationSettings:
    """Attendance duration settings table model."""
    id: int
    dept: str
    min_hours: Decimal
    max_hours: Decimal
    grace_period_minutes: int
    effective_from: date
    effective_to: Optional[date] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class AdminNotification:
    """Admin notifications table model."""
    id: int
    title: str
    message: str
    is_read: bool
    created_at: datetime
    updated_at: datetime


@dataclass
class LeaveRequestAuditLog:
    """Leave request audit log table model."""
    id: int
    leave_request_id: int
    action: str  # 'APPROVED', 'REJECTED', 'CANCELLED'
    performed_by: str
    timestamp: datetime
    remarks: Optional[str] = None


@dataclass
class FaceReregisterRequest:
    """Face reregister requests table model."""
    id: int
    reg_no: str
    requested_at: datetime
    reason: str
    status: str  # 'PENDING', 'APPROVED', 'REJECTED'
    processed_by: Optional[str] = None
    processed_at: Optional[datetime] = None


@dataclass
class StaffStudentPermission:
    """Staff student permission delegation table model."""
    id: int
    grantor_staff_reg_no: str
    grantee_staff_reg_no: str
    student_reg_no: Optional[str] = None  # None means ALL students owned by grantor
    permission_type: str = 'MARK_ATTENDANCE'
    valid_from: Optional[datetime] = None
    valid_until: Optional[datetime] = None
    status: str = 'ACTIVE'  # 'ACTIVE', 'REVOKED', 'EXPIRED'
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class Student:
    """University student profile model."""
    id: int
    reg_no: str
    name: str
    dob: date
    gender: str
    dept: str
    batch: str
    year_of_study: int
    semester: int
    section: str
    parent_phone: str
    registered_by: str
    registered_role: str
    roll_no: Optional[str] = None
    email: Optional[str] = None
    phone_number: Optional[str] = None
    blood_group: Optional[str] = None
    degree: str = 'B.E.'
    quota: str = 'Govt'
    mentor_staff_reg_no: Optional[str] = None
    father_name: Optional[str] = None
    mother_name: Optional[str] = None
    parent_email: Optional[str] = None
    emergency_contact: Optional[str] = None
    permanent_address: Optional[str] = None
    city: Optional[str] = None
    state: str = 'Tamil Nadu'
    pincode: Optional[str] = None
    password_hash: Optional[str] = None
    first_time_login: bool = True
    is_active: bool = True
    suspended: bool = False
    can_reregister: bool = False
    current_device_id: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class StudentFaceEmbedding:
    """Individual face sample embedding model."""
    id: int
    student_reg_no: str
    pose_angle: str
    embedding_vector: bytes
    quality_score: float = 1.0
    liveness_score: float = 1.0
    model_version: str = 'arcface_buffalo_s_v1'
    created_at: Optional[datetime] = None


@dataclass
class StudentFacePrototype:
    """Reduced centroid face prototype vector model."""
    student_reg_no: str
    centroid_vector: bytes
    total_samples: int = 3
    average_quality: float = 1.0
    updated_at: Optional[datetime] = None


@dataclass
class StudentAttendance:
    """Student attendance record model."""
    id: int
    student_reg_no: str
    date: date
    session: str  # 'FN', 'AN', 'PERIOD_1', etc.
    status: str  # 'Present', 'Absent', 'OD', 'Leave', 'Medical', 'Holiday'
    marked_by: str
    sub_status: Optional[str] = None  # 'OD_ACADEMIC', 'OD_SPORTS', 'OD_PLACEMENT', 'MEDICAL', 'CASUAL'
    subject_code: Optional[str] = None
    period_number: Optional[int] = None
    day_type: str = 'NORMAL'  # 'NORMAL', 'APPROVED_OD', 'APPROVED_LEAVE', 'APPROVED_MEDICAL', 'HOLIDAY'
    is_auto_declared: bool = False
    attendance_value: Optional[Decimal] = Decimal("1.0")
    document_proof_url: Optional[str] = None
    kiosk_session_uuid: Optional[str] = None
    confidence_score: Optional[float] = None
    marked_at: Optional[datetime] = None


@dataclass
class StudentAcademicDayStatus:
    """Student Academic Day Status registry."""
    id: int
    student_reg_no: str
    date: date
    day_type: str  # 'NORMAL', 'APPROVED_OD', 'APPROVED_LEAVE', 'APPROVED_MEDICAL', 'HOLIDAY'
    reason: Optional[str] = None
    leave_request_id: Optional[int] = None
    declared_by: str = 'SYSTEM'
    attendance_value: Optional[Decimal] = Decimal("1.0")
    declared_at: Optional[datetime] = None


@dataclass
class StudentLeaveODRequest:
    """Student leave and On-Duty request model."""
    id: int
    student_reg_no: str
    request_type: str
    start_date: date
    end_date: date
    reason: str
    session_half: str = 'FULL_DAY'
    document_proof_url: Optional[str] = None
    mentor_status: str = 'PENDING'
    hod_status: str = 'PENDING'
    approved_by: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class StaffSessionNote:
    """Staff session lesson notes and topics covered."""
    id: int
    staff_reg_no: str
    timetable_slot_id: int
    session_date: date
    subject_code: str
    topic_covered: str
    learning_objectives: Optional[str] = None
    assignment_notes: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


@dataclass
class StaffSessionReminderPreference:
    """Staff session reminder and notification preferences."""
    staff_reg_no: str
    lead_time_minutes: int = 15
    daily_digest_enabled: bool = True
    daily_digest_time: str = '08:00'
    notify_on_substitution: bool = True
    notify_on_relocation: bool = True
    updated_at: Optional[datetime] = None